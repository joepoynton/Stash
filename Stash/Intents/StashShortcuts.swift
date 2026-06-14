//
//  StashShortcuts.swift
//  Stash
//
//  Exposes the three core intents to Spotlight and the Shortcuts app with
//  natural-language trigger phrases, so they work immediately on iOS 18 —
//  before the iOS 26/27 Siri + Apple Intelligence enhancements arrive and start
//  matching looser, unscripted phrasings automatically.
//
//  Every phrase must contain \(.applicationName); "Stash" (and any App Name
//  synonyms the user has set) stands in for it at runtime. Each phrase may
//  reference at most one intent parameter.
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
    }
}
