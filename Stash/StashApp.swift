//
//  StashApp.swift
//  Stash
//

import SwiftUI
import SwiftData

@main
struct StashApp: App {
    @State private var storeKit = StoreKitManager()

    /// True when the CloudKit-backed store failed to open and we fell back
    /// to a local-only store. Surfaces a non-blocking banner in ContentView.
    private let cloudSyncUnavailable: Bool

    private let sharedModelContainer: ModelContainer

    init() {
        // Single process-wide container (see StashModelContainer). The App
        // Intents / Spotlight layer reads and writes the same store, and may
        // create it first if the system launches the app into the background to
        // answer a Siri or Spotlight request. CloudKit config and the
        // local-only fallback live there, unchanged.
        sharedModelContainer = StashModelContainer.shared
        cloudSyncUnavailable = StashModelContainer.cloudSyncUnavailable

        // Launch-time safety pass: sever any parent cycles (possible via
        // CloudKit merges) before any view walks the tree.
        Location.repairCycles(in: sharedModelContainer.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(showSyncUnavailableBanner: cloudSyncUnavailable)
                .environment(storeKit)
                // Build the Spotlight index on launch and keep it in sync with
                // the store thereafter (added / renamed / moved / deleted items).
                .task { SpotlightIndexer.start() }
        }
        .modelContainer(sharedModelContainer)
    }
}
