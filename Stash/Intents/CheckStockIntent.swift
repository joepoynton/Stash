//
//  CheckStockIntent.swift
//  Stash
//
//  "How many <item> do I have" — totals stock for an item across every
//  location it lives in. Takes a free string rather than a single ItemEntity
//  precisely because the answer should sum duplicates rather than make the user
//  pick one location.
//

import Foundation
import AppIntents

struct CheckStockIntent: AppIntent {

    static let title: LocalizedStringResource = "Check Stock"

    static let description = IntentDescription(
        "Check how many of an item you have, added up across every location.",
        categoryName: "Stash"
    )

    /// A product (an item across all its locations). Backed by ProductEntityQuery,
    /// which dedupes by name, so this resolves straight to one product to total
    /// rather than asking the user to pick a location.
    @Parameter(title: "Item")
    var product: ProductEntity

    static var parameterSummary: some ParameterSummary {
        Summary("How many \(\.$product) do I have")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let matches = IntentStore.items(productID: product.id)

        guard !matches.isEmpty else {
            return .result(dialog: IntentDialog("I couldn't find \(product.name) in Stash."))
        }

        let tracked = matches.filter { $0.quantity != nil }

        // Items exist but none have quantity tracking switched on.
        guard !tracked.isEmpty else {
            let places = distinctLocationCount(matches)
            let placePhrase = places > 1 ? " in \(places) places" : ""
            return .result(dialog: IntentDialog(
                "You have \(product.name)\(placePhrase), but quantity tracking is off for it."
            ))
        }

        // Sum quantities, grouped by unit (units are free text, so a user could
        // have "6 cans" in one place and "2 boxes" in another).
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
            .map { IntentFormatting.quantityPhrase($0.total, unit: $0.unit) }
        let totalPhrase = Self.joinWithAnd(phrases)

        let places = distinctLocationCount(tracked)
        let placePhrase = places > 1 ? " across \(places) places" : ""

        return .result(dialog: IntentDialog("You have \(totalPhrase)\(placePhrase)."))
    }

    private func distinctLocationCount(_ items: [Item]) -> Int {
        Set(items.compactMap { $0.location?.id }).count
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
