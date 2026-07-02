//
//  CheckStockIntent.swift
//  Stash
//
//  "How many <item> do I have" — totals stock for an item across every
//  location it lives in. Resolves to a ProductEntity (deduped by name) rather
//  than a single ItemEntity precisely because the answer should sum duplicates
//  rather than make the user pick one location.
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
    @Parameter(title: "Item", requestValueDialog: "Which item do you want to check?")
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

        // Items exist but none have quantity tracking switched on.
        guard let totalPhrase = IntentFormatting.totalStockPhrase(for: matches) else {
            let places = distinctLocationCount(matches)
            let placePhrase = places > 1 ? " in \(places) places" : ""
            return .result(dialog: IntentDialog(
                "You have \(product.name)\(placePhrase), but quantity tracking is off for it."
            ))
        }

        let tracked = matches.filter { $0.quantity != nil }
        let places = distinctLocationCount(tracked)

        // Name the place when there's exactly one; otherwise give the count so
        // the natural follow-up ("find my …") is obvious.
        let placePhrase: String
        if places == 1, let path = tracked.first?.location?.pathString {
            placePhrase = ", in \(path)"
        } else if places > 1 {
            placePhrase = " across \(places) places"
        } else {
            placePhrase = ""
        }

        return .result(dialog: IntentDialog("You have \(totalPhrase)\(placePhrase)."))
    }

    private func distinctLocationCount(_ items: [Item]) -> Int {
        Set(items.compactMap { $0.location?.id }).count
    }
}
