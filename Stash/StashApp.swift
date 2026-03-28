//
//  StashApp.swift
//  Stash
//

import SwiftUI
import SwiftData

@main
struct StashApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Location.self, Item.self])
        // CloudKit sync via .automatic (uses iCloud.Poynt.Stash container).
        // Requires iCloud + CloudKit capabilities in Xcode and the container
        // provisioned in the Apple Developer portal.
        // Falls back to local-only storage if iCloud is unavailable.
        let config = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
