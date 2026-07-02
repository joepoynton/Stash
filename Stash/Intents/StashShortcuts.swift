//
//  StashShortcuts.swift
//  Stash
//
//  Exposes the core intents to Spotlight and the Shortcuts app with
//  natural-language trigger phrases, so they work immediately on iOS 18. On
//  the iOS 27 generation these fixed phrases become the floor, not the
//  ceiling — Apple Intelligence matches looser, unscripted phrasings against
//  the intents' titles, descriptions and entity-typed parameters directly.
//
//  Rules the appintentsmetadataprocessor enforces:
//  - Every phrase must contain \(.applicationName); "Stash" (and any App Name
//    synonyms the user has set) stands in for it at runtime.
//  - Each phrase may reference at most one intent parameter, and it must be
//    an AppEntity/AppEnum. (MoveItem therefore carries only the item — Siri
//    asks "Where should it go?" as a follow-up turn.)
//
//  SpotlightIndexer calls updateAppShortcutParameters() after every reindex
//  so the parameter vocabulary (item / space names) tracks the inventory.
//

import AppIntents

struct StashShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: FindItemIntent(),
            phrases: [
                "Where is my \(\.$item) in \(.applicationName)",
                "Where's my \(\.$item) in \(.applicationName)",
                "Find my \(\.$item) in \(.applicationName)",
                "Where did I put my \(\.$item) in \(.applicationName)",
                "Locate my \(\.$item) in \(.applicationName)"
            ],
            shortTitle: "Find Item",
            systemImageName: "magnifyingglass"
        )

        AppShortcut(
            intent: CheckStockIntent(),
            phrases: [
                "How many \(\.$product) do I have in \(.applicationName)",
                "How much \(\.$product) do I have in \(.applicationName)",
                "Check my \(\.$product) stock in \(.applicationName)",
                "Do I have any \(\.$product) in \(.applicationName)"
            ],
            shortTitle: "Check Stock",
            systemImageName: "number"
        )

        AppShortcut(
            intent: UseItemIntent(),
            phrases: [
                "I used a \(\.$item) in \(.applicationName)",
                "I used some \(\.$item) in \(.applicationName)",
                "Use a \(\.$item) in \(.applicationName)",
                "Take a \(\.$item) from \(.applicationName)"
            ],
            shortTitle: "Use Item",
            systemImageName: "minus.circle"
        )

        AppShortcut(
            intent: WhatsInLocationIntent(),
            phrases: [
                "What's in my \(\.$space) in \(.applicationName)",
                "What's inside my \(\.$space) in \(.applicationName)",
                "Show me what's in my \(\.$space) in \(.applicationName)",
                "What do I have in my \(\.$space) in \(.applicationName)"
            ],
            shortTitle: "What's Inside",
            systemImageName: "archivebox"
        )

        AppShortcut(
            intent: ExpiringItemsIntent(),
            phrases: [
                "What's expiring soon in \(.applicationName)",
                "What's about to expire in \(.applicationName)",
                "What's expired in \(.applicationName)",
                "Show expiring items in \(.applicationName)"
            ],
            shortTitle: "What's Expiring",
            systemImageName: "clock.badge.exclamationmark"
        )

        AppShortcut(
            intent: RestockListIntent(),
            phrases: [
                "What do I need to buy in \(.applicationName)",
                "What am I low on in \(.applicationName)",
                "What needs restocking in \(.applicationName)",
                "Show my restock list in \(.applicationName)"
            ],
            shortTitle: "What to Buy",
            systemImageName: "cart"
        )

        AppShortcut(
            intent: MoveItemIntent(),
            phrases: [
                "Move my \(\.$item) in \(.applicationName)",
                "Move an item in \(.applicationName)",
                "Put my \(\.$item) somewhere else in \(.applicationName)"
            ],
            shortTitle: "Move Item",
            systemImageName: "arrow.up.arrow.down"
        )

        AppShortcut(
            intent: RestockItemIntent(),
            phrases: [
                "I bought more \(\.$item) in \(.applicationName)",
                "I restocked my \(\.$item) in \(.applicationName)",
                "Restock an item in \(.applicationName)"
            ],
            shortTitle: "Restock Item",
            systemImageName: "plus.circle"
        )
    }
}
