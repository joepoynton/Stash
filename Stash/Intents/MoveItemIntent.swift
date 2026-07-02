//
//  MoveItemIntent.swift
//  Stash
//
//  "Move the drill to the loft" — rehomes an item, using exactly the same
//  mutation as the in-app Move sheet (set location, bump lastVerified).
//
//  Multi-turn by design: the App Shortcut phrase carries only the item, so
//  Siri asks "Where should it go?" for the destination — and both parameters
//  disambiguate through their entity queries (breadcrumb subtitles + photos)
//  when several match. On iOS 27, View Annotations let "this" stand in for
//  the item when its detail view is on screen.
//

import Foundation
import AppIntents

struct MoveItemIntent: AppIntent {

    static let title: LocalizedStringResource = "Move an Item"

    static let description = IntentDescription(
        "Move one of your items to a different space.",
        categoryName: "Stash"
    )

    @Parameter(title: "Item", requestValueDialog: "Which item do you want to move?")
    var item: ItemEntity

    @Parameter(title: "Destination", requestValueDialog: "Where should it go?")
    var destination: LocationEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Move \(\.$item) to \(\.$destination)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<ItemEntity> {
        guard let liveItem = IntentStore.item(id: item.id) else {
            return .result(
                value: item,
                dialog: IntentDialog("I can't find \(item.name) in Stash anymore.")
            )
        }
        guard let liveDestination = IntentStore.location(id: destination.id) else {
            return .result(
                value: ItemEntity(item: liveItem),
                dialog: IntentDialog("I can't find \(destination.name) in Stash anymore.")
            )
        }

        if liveItem.location?.id == liveDestination.id {
            return .result(
                value: ItemEntity(item: liveItem),
                dialog: IntentDialog("\(liveItem.name) is already in \(liveDestination.pathString).")
            )
        }

        // Same mutation as ItemDetailSheet's Move sheet: rehome + verify.
        liveItem.location = liveDestination
        liveItem.lastVerified = Date()
        IntentStore.save()
        await SpotlightIndexer.index(liveItem)

        return .result(
            value: ItemEntity(item: liveItem),
            dialog: IntentDialog("Moved \(liveItem.name) to \(liveDestination.pathString).")
        )
    }
}
