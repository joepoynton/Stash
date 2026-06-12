//
//  StashApp.swift
//  Stash
//

import SwiftUI
import SwiftData
import os

@main
struct StashApp: App {
    @State private var storeKit = StoreKitManager()

    /// True when the CloudKit-backed store failed to open and we fell back
    /// to a local-only store. Surfaces a non-blocking banner in ContentView.
    private let cloudSyncUnavailable: Bool

    private let sharedModelContainer: ModelContainer

    init() {
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Poynt.Stash", category: "Startup")
        let schema = Schema([Location.self, Item.self])
        // CloudKit sync via .automatic (uses iCloud.Poynt.Stash container).
        // Requires iCloud + CloudKit capabilities in Xcode and the container
        // provisioned in the Apple Developer portal.
        let cloudConfig = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
        do {
            sharedModelContainer = try ModelContainer(for: schema, configurations: [cloudConfig])
            cloudSyncUnavailable = false
        } catch {
            // A CloudKit container failure must not crash-loop the app — the
            // user's data is still on disk. Retry without sync.
            logger.error("CloudKit ModelContainer failed (\(error, privacy: .public)). Retrying local-only.")
            let localConfig = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            do {
                sharedModelContainer = try ModelContainer(for: schema, configurations: [localConfig])
                cloudSyncUnavailable = true
            } catch {
                fatalError("Could not create ModelContainer even without CloudKit: \(error)")
            }
        }

        // Launch-time safety pass: sever any parent cycles (possible via
        // CloudKit merges) before any view walks the tree.
        Location.repairCycles(in: sharedModelContainer.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(showSyncUnavailableBanner: cloudSyncUnavailable)
                .environment(storeKit)
        }
        .modelContainer(sharedModelContainer)
    }
}
