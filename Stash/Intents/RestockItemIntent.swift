//
//  RestockItemIntent.swift
//  Stash
//
//  "I bought more AA batteries" — records a restock through the existing
//  Item.markAsArrived(count:), which adds to a tracked quantity, clears the
//  on-order and manual-restock flags, and bumps lastVerified. It deliberately
//  never switches quantity tracking on for an untracked item — same guard as
//  everywhere else in the app.
//

import Foundation
import AppIntents

struct RestockItemIntent: AppIntent {

    static let title: LocalizedStringResource = "Restock an Item"

    static let description = IntentDescription(
        "Record that you bought or received more of an item, counting its quantity up.",
        categoryName: "Stash"
    )

    @Parameter(title: "Item", requestValueDialog: "Which item did you restock?")
    var item: ItemEntity

    @Parameter(title: "How Many", default: 1, inclusiveRange: (1, 9_999))
    var count: Int

    static var parameterSummary: some ParameterSummary {
        Summary("I bought \(\.$count) more \(\.$item)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<ItemEntity> {
        guard let live = IntentStore.item(id: item.id) else {
            return .result(
                value: item,
                dialog: IntentDialog("I can't find \(item.name) in Stash anymore.")
            )
        }

        let wasTracked = live.quantity != nil
        live.markAsArrived(count: max(1, count))
        IntentStore.save()
        await SpotlightIndexer.index(live)

        let dialog: String
        if wasTracked {
            let total = IntentFormatting.quantityPhrase(live.quantity ?? 0, unit: live.unit)
            dialog = "Done — you now have \(total) of \(live.name)."
        } else {
            dialog = "Marked \(live.name) as restocked. Quantity tracking is off for it, so I haven't changed a count."
        }

        return .result(
            value: ItemEntity(item: live),
            dialog: IntentDialog("\(dialog)")
        )
    }
}
