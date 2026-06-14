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
}
