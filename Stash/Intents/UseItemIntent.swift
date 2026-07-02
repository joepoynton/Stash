//
//  UseItemIntent.swift
//  Stash
//
//  "I used one <item>" / "I used <n> <item>" — counts an item down by the given
//  amount (default 1) using the existing Item.updateQuantity method.
//
//  Disambiguation across locations is automatic: the `item` parameter is backed
//  by ItemEntityQuery, so when a name matches the same product in several places
//  the system asks the user which one (each option shows its location path).
//

import Foundation
import AppIntents

struct UseItemIntent: AppIntent {

    static let title: LocalizedStringResource = "Use an Item"

    static let description = IntentDescription(
        "Record that you used some of an item, counting its quantity down.",
        categoryName: "Stash"
    )

    @Parameter(title: "Item", requestValueDialog: "Which item did you use?")
    var item: ItemEntity

    @Parameter(title: "Number Used", default: 1, inclusiveRange: (1, 9_999))
    var count: Int

    static var parameterSummary: some ParameterSummary {
        Summary("I used \(\.$count) \(\.$item)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<ItemEntity> {
        guard let live = IntentStore.item(id: item.id) else {
            return .result(
                value: item,
                dialog: IntentDialog("I can't find \(item.name) in Stash anymore.")
            )
        }

        let amount = max(1, count)

        // Never switch quantity tracking on for an untracked item — mirrors the
        // app's own guard on incrementing/decrementing.
        guard let current = live.quantity else {
            return .result(
                value: ItemEntity(item: live),
                dialog: IntentDialog("Quantity tracking is off for \(live.name), so there's nothing to count down.")
            )
        }

        // Reuse the existing model write method (clamps to >= 0, bumps lastVerified,
        // and clears a stale on-order flag if appropriate).
        live.updateQuantity(to: current - amount)
        IntentStore.save()
        await SpotlightIndexer.index(live)

        return .result(
            value: ItemEntity(item: live),
            dialog: IntentDialog("\(Self.confirmation(for: live, previous: current))")
        )
    }

    /// "Done — you now have 2 batteries left." (with low-stock and out-of-stock
    /// variants).
    static func confirmation(for item: Item, previous: Int) -> String {
        let newValue = item.quantity ?? 0

        if previous == 0 {
            return "You're already out of \(item.name)."
        }
        if newValue == 0 {
            return "Done — that was your last \(item.name). You're now out."
        }

        var message = "Done — you now have \(IntentFormatting.quantityPhrase(newValue, unit: item.unit)) left."
        if let minimum = item.minimumQuantity, newValue < minimum {
            message += " You're running low."
        }
        return message
    }
}
