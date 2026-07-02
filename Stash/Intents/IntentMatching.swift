//
//  IntentMatching.swift
//  Stash
//
//  Shared natural-language matching for the entity queries. Siri and Apple
//  Intelligence hand our queries whatever span of speech they attributed to
//  the parameter, so exact `contains` matching alone drops easy cases like
//  "batteries" vs an item named "AA Battery". Every query (item, location,
//  product) funnels through here so they all get the same behaviour:
//
//    1. exact name match          (rank 0)
//    2. name prefix match         (rank 1)
//    3. name contains the query   (rank 2)
//    4. every query token stem-matches a candidate token  (rank 3)
//
//  Stemming is deliberately crude (strip plural suffixes) and applied to BOTH
//  sides, so "batteries" ⇄ "battery", "boxes" ⇄ "box". A lower rank sorts
//  first, which is what the disambiguation UI shows at the top.
//

import Foundation

enum IntentMatching {

    /// Lowercased, diacritic-folded word tokens.
    static func tokens(_ string: String) -> [String] {
        string
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// Crude plural-stripping stem. Symmetric use (both query and candidate
    /// are stemmed) means imperfect stems still match each other.
    static func stem(_ token: String) -> String {
        if token.count > 3, token.hasSuffix("ies") {
            return token.dropLast(3) + "y"
        }
        if token.count > 3, token.hasSuffix("es") {
            return String(token.dropLast(2))
        }
        if token.count > 2, token.hasSuffix("s") {
            return String(token.dropLast())
        }
        return token
    }

    /// Match rank of `query` against `candidate`, or nil when it doesn't
    /// match. Lower is better; see the tiers in the header comment.
    static func rank(query: String, candidate: String) -> Int? {
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
        guard !trimmedQuery.isEmpty else { return nil }

        if candidate.localizedCaseInsensitiveCompare(trimmedQuery) == .orderedSame { return 0 }

        let foldedCandidate = candidate.folding(
            options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let foldedQuery = trimmedQuery.folding(
            options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        if foldedCandidate.hasPrefix(foldedQuery) { return 1 }
        if candidate.localizedStandardContains(trimmedQuery) { return 2 }

        let queryStems = tokens(trimmedQuery).map(stem)
        guard !queryStems.isEmpty else { return nil }
        let candidateStems = Set(tokens(candidate).map(stem))
        let allTokensMatch = queryStems.allSatisfy { queryStem in
            candidateStems.contains(queryStem)
                || candidateStems.contains { $0.hasPrefix(queryStem) }
        }
        return allTokensMatch ? 3 : nil
    }

    /// Convenience boolean form of `rank(query:candidate:)`.
    static func matches(query: String, candidate: String) -> Bool {
        rank(query: query, candidate: candidate) != nil
    }

    /// Ranks `candidates` against `query` using `name` as the primary match
    /// field and `secondary` (e.g. location path + notes) as a fallback field,
    /// returning matches best-first. Secondary-only matches rank after every
    /// name match.
    static func rankedMatches<T>(
        query: String,
        candidates: [T],
        name: (T) -> String,
        secondary: (T) -> String = { _ in "" }
    ) -> [T] {
        candidates
            .compactMap { candidate -> (candidate: T, rank: Int)? in
                if let nameRank = rank(query: query, candidate: name(candidate)) {
                    return (candidate, nameRank)
                }
                // Secondary text gets a flat, worse-than-any-name rank: it
                // exists to catch "garage keys" style queries, not to compete
                // with real name matches.
                if matches(query: query, candidate: secondary(candidate)) {
                    return (candidate, 10)
                }
                return nil
            }
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
                return name(lhs.candidate).localizedStandardCompare(name(rhs.candidate)) == .orderedAscending
            }
            .map(\.candidate)
    }
}
