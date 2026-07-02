//
//  IntentRouter.swift
//  Stash
//
//  Bridge between intents that open the app (OpenItem, OpenLocation, Search)
//  and the SwiftUI navigation layer. Intents run in the app's process but
//  can't reach the NavigationState instance living in ContentView's @State —
//  and when an intent cold-launches the app, the view hierarchy doesn't even
//  exist yet when perform() runs. So intents post *pending* destinations here,
//  and the views consume them whenever they're ready (onChange for the warm
//  case, onAppear/task for the cold-launch case).
//
//  Also the landing spot for Spotlight tap-throughs (CSSearchableItemActionType
//  user activities), whose identifiers we parse back to entity UUIDs.
//

import Foundation
import Observation

@MainActor
@Observable
final class IntentRouter {

    static let shared = IntentRouter()

    /// Item to present in a detail sheet (consumed by ContentView).
    var pendingItemID: UUID?

    /// Location to deep-link Browse into (consumed by ContentView).
    var pendingLocationID: UUID?

    /// Search text to run in Browse (consumed by BrowseTab).
    var pendingSearchText: String?

    private init() {}

    func openItem(_ id: UUID) {
        pendingItemID = id
    }

    func openLocation(_ id: UUID) {
        pendingLocationID = id
    }

    func search(_ text: String) {
        pendingSearchText = text
    }

    /// Routes a tapped Spotlight result. Identifiers for records indexed via
    /// indexAppEntities are derived from the entity id, but the exact format
    /// is the system's business — so try the whole string and then each
    /// separator-delimited component until one parses as a UUID we recognise.
    func handleSpotlightIdentifier(_ identifier: String) {
        var candidates = [identifier]
        for separator in ["/", ":", "."] {
            candidates.append(contentsOf: identifier.components(separatedBy: separator))
        }

        for candidate in candidates {
            guard let id = UUID(uuidString: candidate) else { continue }
            if IntentStore.item(id: id) != nil {
                openItem(id)
                return
            }
            if IntentStore.location(id: id) != nil {
                openLocation(id)
                return
            }
        }
    }
}
