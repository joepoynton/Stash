//
//  RecentlyAccessedStore.swift
//  Stash
//
//  Tracks the 8 most recently viewed items.
//  Deduplicates: same item viewed within 10 minutes counts once.
//  Persists to UserDefaults as JSON.
//

import Foundation
import Observation

private struct RecentAccessEntry: Codable {
    let itemID: String
    var accessedAt: Date
}

@Observable
final class RecentlyAccessedStore {
    /// Item UUIDs in most-recent-first order. Observe this to update UI.
    private(set) var orderedIDs: [String] = []

    private let key = "recentlyAccessedEntries"
    private let maxEntries = 8
    private let dedupWindow: TimeInterval = 600  // 10 minutes

    private var entries: [RecentAccessEntry] = [] {
        didSet { orderedIDs = entries.map(\.itemID) }
    }

    init() {
        load()
    }

    func record(itemID: UUID) {
        let idString = itemID.uuidString
        let now = Date()

        // If the same item was accessed within the dedup window, skip
        if let existing = entries.first(where: { $0.itemID == idString }),
           now.timeIntervalSince(existing.accessedAt) < dedupWindow {
            return
        }

        entries.removeAll { $0.itemID == idString }
        entries.insert(RecentAccessEntry(itemID: idString, accessedAt: now), at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([RecentAccessEntry].self, from: data)
        else { return }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
