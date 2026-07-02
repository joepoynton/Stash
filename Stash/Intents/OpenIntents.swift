//
//  OpenIntents.swift
//  Stash
//
//  The system-defined intent shapes Stash adopts. Apple Intelligence and the
//  semantic index understand these protocols natively — no phrases needed:
//
//  - OpenIntent (OpenItemIntent / OpenLocationIntent): the canonical
//    "open this entity in its app" action. Backs Spotlight tap-through,
//    "open my work bag in Stash", and Shortcuts' Open actions.
//  - ShowInAppSearchResultsIntent (SearchStashIntent): the canonical
//    "search inside this app" action — "search Stash for camping gear"
//    lands directly in Browse's existing search UI.
//
//  (The Assistant Schema domains — mail, photos, browser, documents… — were
//  assessed and none maps onto a personal inventory; see EntityAnnotations.swift
//  for the iOS 27 seam. These two system intents are the ones that fit.)
//
//  All three just post to IntentRouter; the SwiftUI layer consumes the
//  pending destination once the scene is on screen.
//

import Foundation
import AppIntents

// MARK: - Open an item

struct OpenItemIntent: OpenIntent {

    static let title: LocalizedStringResource = "Open an Item"

    static let description = IntentDescription(
        "Open one of your items in Stash.",
        categoryName: "Stash"
    )

    @Parameter(title: "Item", requestValueDialog: "Which item do you want to open?")
    var target: ItemEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$target)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRouter.shared.openItem(target.id)
        return .result()
    }
}

// MARK: - Open a space

struct OpenLocationIntent: OpenIntent {

    static let title: LocalizedStringResource = "Open a Space"

    static let description = IntentDescription(
        "Open one of your spaces in Stash to browse what's inside.",
        categoryName: "Stash"
    )

    @Parameter(title: "Space", requestValueDialog: "Which space do you want to open?")
    var target: LocationEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$target)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRouter.shared.openLocation(target.id)
        return .result()
    }
}

// MARK: - In-app search

struct SearchStashIntent: ShowInAppSearchResultsIntent {

    static let title: LocalizedStringResource = "Search Stash"

    static let description = IntentDescription(
        "Search your inventory — items, spaces and notes.",
        categoryName: "Stash"
    )

    static let searchScopes: [StringSearchScope] = [.general]

    @Parameter(title: "Search")
    var criteria: StringSearchCriteria

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRouter.shared.search(criteria.term)
        return .result()
    }
}
