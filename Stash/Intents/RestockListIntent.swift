//
//  RestockListIntent.swift
//  Stash
//
//  "What do I need to buy" — reads the same Item.needsRestock definition the
//  Restock tab uses, split into things still to buy versus things already on
//  order, so Siri's answer always matches the tab.
//

import Foundation
import AppIntents

struct RestockListIntent: AppIntent {

    static let title: LocalizedStringResource = "What to Buy"

    static let description = IntentDescription(
        "List everything on your Restock list — items running low or added by hand.",
        categoryName: "Stash"
    )

    static var parameterSummary: some ParameterSummary {
        Summary("What do I need to buy")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<[ItemEntity]> {
        let restock = IntentStore.restockItems()
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        guard !restock.isEmpty else {
            return .result(
                value: [],
                dialog: IntentDialog("You're fully stocked — nothing needs buying.")
            )
        }

        // Things already on order aren't "to buy" — count them separately.
        let toBuy = restock.filter { !$0.isOnOrder }
        let onOrder = restock.filter(\.isOnOrder)
        let entities = (toBuy + onOrder).map(ItemEntity.init)

        return .result(
            value: entities,
            dialog: IntentDialog("\(Self.restockDialog(toBuy: toBuy, onOrder: onOrder))")
        )
    }

    /// "You need 3 things: coffee, AA batteries and bin bags. 2 more are
    /// already on order."
    static func restockDialog(toBuy: [Item], onOrder: [Item]) -> String {
        var sentences: [String] = []
        let spokenNameCap = 5

        if !toBuy.isEmpty {
            let names = toBuy.prefix(spokenNameCap).map(\.name)
            var sentence = toBuy.count == 1
                ? "You need 1 thing: \(names[0])"
                : "You need \(toBuy.count) things: \(IntentFormatting.joinWithAnd(names))"
            if toBuy.count > spokenNameCap {
                sentence += ", and \(toBuy.count - spokenNameCap) more"
            }
            sentences.append(sentence + ".")
        }

        if !onOrder.isEmpty {
            if toBuy.isEmpty {
                sentences.append(onOrder.count == 1
                    ? "Nothing to buy — 1 item is already on order."
                    : "Nothing to buy — \(onOrder.count) items are already on order.")
            } else {
                sentences.append(onOrder.count == 1
                    ? "1 more is already on order."
                    : "\(onOrder.count) more are already on order.")
            }
        }

        return sentences.joined(separator: " ")
    }
}
