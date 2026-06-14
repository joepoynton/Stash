//
//  StashModelContainer.swift
//  Stash
//
//  Single shared ModelContainer for the whole app.
//
//  Both the SwiftUI scene (StashApp) and the App Intents / App Entities use
//  this one container. App Intents can be launched by the system into a
//  background process to answer Siri / Spotlight requests *before* the
//  SwiftUI App scene exists, so the container must be obtainable without
//  depending on the App lifecycle. A lazily-initialised static gives us
//  exactly one container, created on first access from whichever side runs
//  first, with the same CloudKit configuration and the same local-only
//  fallback the app has always used.
//

import Foundation
import SwiftData
import os

enum StashModelContainer {

    /// True when the CloudKit-backed store failed to open and we fell back to
    /// a local-only store. Read by StashApp to surface its sync banner.
    /// Only ever written once, inside the `shared` initialiser closure.
    private(set) static var cloudSyncUnavailable = false

    /// The process-wide container. Configuration is intentionally identical to
    /// the store the app has shipped with — schema `[Location, Item]`, CloudKit
    /// `.automatic`, local-only retry on failure. Do not change the schema or
    /// CloudKit settings here.
    static let shared: ModelContainer = {
        let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "Poynt.Stash",
            category: "Startup"
        )
        let schema = Schema([Location.self, Item.self])
        let cloudConfig = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
        do {
            return try ModelContainer(for: schema, configurations: [cloudConfig])
        } catch {
            // A CloudKit container failure must not crash-loop the app — the
            // user's data is still on disk. Retry without sync.
            logger.error("CloudKit ModelContainer failed (\(error, privacy: .public)). Retrying local-only.")
            let localConfig = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            do {
                let container = try ModelContainer(for: schema, configurations: [localConfig])
                cloudSyncUnavailable = true
                return container
            } catch {
                fatalError("Could not create ModelContainer even without CloudKit: \(error)")
            }
        }
    }()
}
