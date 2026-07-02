//
//  IntentFormatting.swift
//  Stash
//
//  Small phrasing helpers shared by the App Entities and Intents so the
//  spoken / written dialogue reads naturally and consistently.
//

import Foundation

enum IntentFormatting {

    /// A human phrase for a quantity + free-text unit, e.g. "3 cans", "1 box",
    /// or just "3" when there is no unit. Units are user free text, so they are
    /// never pluralised — we render them exactly as the user typed them.
    static func quantityPhrase(_ quantity: Int, unit: String?) -> String {
        if let unit, !unit.trimmingCharacters(in: .whitespaces).isEmpty {
            return "\(quantity) \(unit)"
        }
        return "\(quantity)"
    }

    /// A short summary of an item's stock for display in entity rows and
    /// Spotlight, e.g. "3 cans" or "Not tracked" when quantity tracking is off.
    static func stockSummary(quantity: Int?, unit: String?) -> String {
        guard let quantity else { return "Not tracked" }
        return quantityPhrase(quantity, unit: unit)
    }

    /// Totals tracked stock across `items`, grouped by unit (units are free
    /// text, so "6 cans" in one place and "2 boxes" in another must not be
    /// merged), e.g. "6 cans and 2 boxes". Nil when nothing is tracked.
    /// Shared by CheckStockIntent's dialogue and ProductEntity's subtitle.
    static func totalStockPhrase(for items: [Item]) -> String? {
        let tracked = items.filter { $0.quantity != nil }
        guard !tracked.isEmpty else { return nil }

        var groupOrder: [String] = []
        var groups: [String: (unit: String?, total: Int)] = [:]
        for item in tracked {
            let quantity = item.quantity ?? 0
            let key = (item.unit?.trimmingCharacters(in: .whitespaces).lowercased()) ?? ""
            if let existing = groups[key] {
                groups[key] = (existing.unit, existing.total + quantity)
            } else {
                groups[key] = (item.unit, quantity)
                groupOrder.append(key)
            }
        }

        let phrases = groupOrder.compactMap { groups[$0] }
            .map { quantityPhrase($0.total, unit: $0.unit) }
        return joinWithAnd(phrases)
    }

    /// "a", "a and b", "a, b and c".
    static func joinWithAnd(_ phrases: [String]) -> String {
        switch phrases.count {
        case 0: return ""
        case 1: return phrases[0]
        case 2: return "\(phrases[0]) and \(phrases[1])"
        default:
            let head = phrases.dropLast().joined(separator: ", ")
            return "\(head) and \(phrases.last ?? "")"
        }
    }
}
