//
//  WhatsInLocationIntent.swift
//  Stash
//
//  "What's in my work bag" — lists the contents of a space: the items stored
//  directly in it, plus a rollup of anything in spaces nested inside it. The
//  nested walk reuses the cycle-safe selfAndDescendantIDs helper, so corrupted
//  trees can't hang a Siri request.
//

import Foundation
import AppIntents
// Required for .result(value:dialog:view:) — see note in RestockListIntent.
import SwiftUI

struct WhatsInLocationIntent: AppIntent {

    static let title: LocalizedStringResource = "What's in a Space"

    static let description = IntentDescription(
        "List what's stored in one of your spaces, including anything in spaces nested inside it.",
        categoryName: "Stash"
    )

    @Parameter(title: "Space", requestValueDialog: "Which space?")
    var space: LocationEntity

    static var parameterSummary: some ParameterSummary {
        Summary("What's in \(\.$space)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView & ReturnsValue<[ItemEntity]> {
        guard let live = IntentStore.location(id: space.id) else {
            return .result(
                value: [],
                dialog: IntentDialog("I can't find \(space.name) in Stash anymore."),
                view: ItemListSnippetView(title: space.name, items: [])
            )
        }

        let directItems = live.itemList
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let subtreeItems = IntentStore.items(inSubtreeOf: live)
        let nestedCount = subtreeItems.count - directItems.count
        let childSpaces = live.childList

        // Direct items lead; nested items follow, so the returned collection
        // and the snippet both mirror how the Browse screen presents a space.
        let directIDs = Set(directItems.map(\.id))
        let orderedItems = directItems + subtreeItems
            .filter { !directIDs.contains($0.id) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let entities = orderedItems.map(ItemEntity.init)

        return .result(
            value: entities,
            dialog: IntentDialog("\(Self.contentsDialog(for: live, directItems: directItems, nestedCount: nestedCount, childSpaces: childSpaces))"),
            view: ItemListSnippetView(title: live.pathString, items: entities)
        )
    }

    /// "Work Bag has 3 items: charger, mouse and notebook. Plus 2 more items
    /// in 1 space inside." — capped so the spoken answer stays speakable.
    static func contentsDialog(
        for location: Location,
        directItems: [Item],
        nestedCount: Int,
        childSpaces: [Location]
    ) -> String {
        var sentences: [String] = []
        let spokenNameCap = 5

        if directItems.isEmpty && nestedCount <= 0 {
            return childSpaces.isEmpty
                ? "\(location.name) is empty."
                : "\(location.name) has no items — just \(countPhrase(childSpaces.count, "empty space", "empty spaces"))."
        }

        if directItems.isEmpty {
            sentences.append("\(location.name) has no items directly inside it.")
        } else {
            let names = directItems.prefix(spokenNameCap).map(\.name)
            var listing = "\(location.name) has \(countPhrase(directItems.count, "item", "items")): \(IntentFormatting.joinWithAnd(names))"
            if directItems.count > spokenNameCap {
                listing += ", and \(directItems.count - spokenNameCap) more"
            }
            sentences.append(listing + ".")
        }

        if nestedCount > 0 {
            sentences.append("Plus \(countPhrase(nestedCount, "more item", "more items")) in \(countPhrase(childSpaces.count, "space", "spaces")) inside.")
        }

        return sentences.joined(separator: " ")
    }

    private static func countPhrase(_ count: Int, _ singular: String, _ plural: String) -> String {
        count == 1 ? "1 \(singular)" : "\(count) \(plural)"
    }
}
