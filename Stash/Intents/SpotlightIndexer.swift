//
//  SpotlightIndexer.swift
//  Stash
//
//  Pushes ItemEntity / LocationEntity records into the on-device Spotlight
//  index so Stash content surfaces in system-wide search (the home-screen
//  search field) with attribution back to the app.
//
//  Lifecycle: a full index is built on launch, then the index is rebuilt
//  whenever the SwiftData store saves — which covers items being added,
//  renamed, moved or deleted — without any view needing to call us. We listen
//  to ModelContext.didSave rather than threading an indexing call through every
//  add/edit/delete site, keeping the App Intents layer self-contained.
//

import Foundation
import AppIntents
import CoreSpotlight
import SwiftData
import os

@MainActor
enum SpotlightIndexer {

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Poynt.Stash",
        category: "Spotlight"
    )

    private static var observerToken: NSObjectProtocol?
    private static var pendingReindex: Task<Void, Never>?

    /// Indexes everything now and begins watching the store for changes.
    /// Idempotent — the change observer is installed only once.
    static func start() {
        Task { await reindexAll() }
        startObserving()
    }

    private static func startObserving() {
        guard observerToken == nil else { return }
        observerToken = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in scheduleReindex() }
        }
    }

    /// Coalesces bursts of saves (e.g. a CloudKit merge writing many records)
    /// into a single reindex a moment later.
    private static func scheduleReindex() {
        pendingReindex?.cancel()
        pendingReindex = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await reindexAll()
        }
    }

    /// Rebuilds the Stash portion of the Spotlight index from the current store.
    /// We clear our entities first because `indexAppEntities` only ever adds or
    /// updates records — it never removes them — so a delete or rename would
    /// otherwise leave a stale entry behind.
    static func reindexAll() async {
        let index = CSSearchableIndex.default()
        do {
            let context = StashModelContainer.shared.mainContext
            let items = try context.fetch(FetchDescriptor<Item>()).map(ItemEntity.init)
            let locations = try context.fetch(FetchDescriptor<Location>()).map(LocationEntity.init)

            try await index.deleteAppEntities(ofType: ItemEntity.self)
            try await index.deleteAppEntities(ofType: LocationEntity.self)
            try await index.indexAppEntities(items)
            try await index.indexAppEntities(locations)

            // Keep Siri's phrase-parameter vocabulary ("where is my <item>")
            // in step with the inventory. Piggybacks on the same debounce.
            StashShortcuts.updateAppShortcutParameters()

            logger.info("Spotlight reindex complete: \(items.count) items, \(locations.count) spaces.")
        } catch {
            logger.error("Spotlight reindex failed: \(error, privacy: .public)")
        }
    }

    /// Updates a single item's Spotlight record immediately. Used after a write
    /// intent (e.g. UseItemIntent) which may run in a background-launched
    /// process where the didSave observer was never installed.
    static func index(_ item: Item) async {
        do {
            try await CSSearchableIndex.default().indexAppEntities([ItemEntity(item: item)])
        } catch {
            logger.error("Spotlight single-item index failed: \(error, privacy: .public)")
        }
    }
}
