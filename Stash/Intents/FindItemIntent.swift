//
//  FindItemIntent.swift
//  Stash
//
//  "Where is my <item>" — the flagship intent. Resolves a spoken / typed item
//  name to an ItemEntity and answers with its location and stock in a single
//  spoken sentence, plus a visual card (photo + breadcrumb) as the snippet.
//
//  Disambiguation across locations is automatic: when the spoken name matches
//  the same product in several places, ItemEntityQuery returns all of them and
//  the system asks the user to choose — each option shows its breadcrumb
//  subtitle and photo (see ItemEntity.displayRepresentation).
//

import Foundation
import AppIntents
// Required for .result(value:dialog:view:) — see note in RestockListIntent.
import SwiftUI

struct FindItemIntent: AppIntent {

    static let title: LocalizedStringResource = "Find an Item"

    static let description = IntentDescription(
        "Find where one of your items is stored, and how many you have.",
        categoryName: "Stash"
    )

    /// The item to locate. Backed by ItemEntityQuery, so the system resolves the
    /// spoken name to an item (asking the user to choose if several match).
    @Parameter(title: "Item", requestValueDialog: "Which item are you looking for?")
    var item: ItemEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Where is my \(\.$item)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView & ReturnsValue<ItemEntity> {
        // Re-read live data: the item may have moved or changed since it was
        // resolved, and it may even have been deleted.
        guard let live = IntentStore.item(id: item.id) else {
            let name = item.name
            return .result(
                value: item,
                dialog: IntentDialog("I can't find \(name) in Stash anymore."),
                view: ItemCardSnippetView(item: item)
            )
        }

        let entity = ItemEntity(item: live)
        return .result(
            value: entity,
            dialog: IntentDialog("\(Self.locationDialog(for: live))"),
            view: ItemCardSnippetView(item: entity)
        )
    }

    /// Builds the natural answer, e.g.
    /// "Your electric razor charger is in Garage › Top Shelf. You have 1."
    static func locationDialog(for item: Item) -> String {
        var sentences: [String] = []

        if let location = item.location {
            sentences.append("Your \(item.name) is in \(location.pathString).")
        } else {
            sentences.append("Your \(item.name) doesn't have a location set yet.")
        }

        if let quantity = item.quantity {
            sentences.append("You have \(IntentFormatting.quantityPhrase(quantity, unit: item.unit)).")
        }

        if item.isOutOfPlace {
            if let note = item.outOfPlaceNote, !note.trimmingCharacters(in: .whitespaces).isEmpty {
                sentences.append("Heads up — it's marked out of place: \(note).")
            } else {
                sentences.append("Heads up — it's currently marked out of place.")
            }
        }

        return sentences.joined(separator: " ")
    }
}
