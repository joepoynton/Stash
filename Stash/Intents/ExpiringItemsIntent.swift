//
//  ExpiringItemsIntent.swift
//  Stash
//
//  "What's expiring soon" — anything already expired plus anything expiring
//  within the window. The 30-day default matches the Home tab's Needs
//  Attention section, and the checks are the shared Item.isExpired /
//  Item.expires(within:) helpers, so Siri and the app can never disagree.
//

import Foundation
import AppIntents
// Required for .result(value:dialog:view:) — see note in RestockListIntent.
import SwiftUI

struct ExpiringItemsIntent: AppIntent {

    static let title: LocalizedStringResource = "What's Expiring"

    static let description = IntentDescription(
        "List items that have expired or will expire soon.",
        categoryName: "Stash"
    )

    @Parameter(title: "Within Days", default: 30, inclusiveRange: (1, 365))
    var days: Int

    static var parameterSummary: some ParameterSummary {
        Summary("What's expiring in the next \(\.$days) days")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView & ReturnsValue<[ItemEntity]> {
        let all = IntentStore.allItems()
        let expired = all.filter(\.isExpired)
            .sorted { ($0.expiryDate ?? .distantPast) < ($1.expiryDate ?? .distantPast) }
        let expiringSoon = all.filter { $0.expires(within: days) }
            .sorted { ($0.expiryDate ?? .distantFuture) < ($1.expiryDate ?? .distantFuture) }

        let entities = (expired + expiringSoon).map(ItemEntity.init)
        let title = "Expiring within \(days) days"

        guard !entities.isEmpty else {
            return .result(
                value: [],
                dialog: IntentDialog("Nothing has expired, and nothing expires in the next \(days) days."),
                view: ItemListSnippetView(title: title, items: [])
            )
        }

        return .result(
            value: entities,
            dialog: IntentDialog("\(Self.expiryDialog(expired: expired, expiringSoon: expiringSoon, days: days))"),
            view: ItemListSnippetView(title: title, items: entities)
        )
    }

    /// "2 items have expired: milk and yoghurt. 3 more expire in the next
    /// 30 days." — names the expired ones (most urgent), counts the rest.
    static func expiryDialog(expired: [Item], expiringSoon: [Item], days: Int) -> String {
        var sentences: [String] = []
        let spokenNameCap = 4

        if !expired.isEmpty {
            let names = expired.prefix(spokenNameCap).map(\.name)
            var sentence = expired.count == 1
                ? "1 item has expired: \(names[0])"
                : "\(expired.count) items have expired: \(IntentFormatting.joinWithAnd(names))"
            if expired.count > spokenNameCap {
                sentence += ", and \(expired.count - spokenNameCap) more"
            }
            sentences.append(sentence + ".")
        }

        if !expiringSoon.isEmpty {
            let more = expired.isEmpty ? "" : " more"
            if expiringSoon.count == 1, let item = expiringSoon.first {
                sentences.append("1\(more) item expires in the next \(days) days: \(item.name).")
            } else {
                sentences.append("\(expiringSoon.count)\(more) items expire in the next \(days) days.")
            }
        }

        return sentences.joined(separator: " ")
    }
}
