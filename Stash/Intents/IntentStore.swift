//
//  IntentStore.swift
//  Stash
//
//  Thin MainActor accessor the intents use to read and write live Item objects
//  from the shared SwiftData store. Keeping store access in one place keeps the
//  intents focused on dialogue and behaviour.
//

import Foundation
import SwiftData

@MainActor
enum IntentStore {

    static var context: ModelContext { StashModelContainer.shared.mainContext }

    /// Every item in the store.
    static func allItems() -> [Item] {
        (try? context.fetch(FetchDescriptor<Item>())) ?? []
    }

    /// The live Item for an entity id, or nil if it has since been deleted.
    static func item(id: UUID) -> Item? {
        allItems().first { $0.id == id }
    }

    /// Every item whose name matches the query, case- and diacritic-insensitively
    /// (mirrors in-app search). Used to total stock across multiple locations.
    static func items(matching query: String) -> [Item] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        return allItems().filter { $0.name.localizedStandardContains(trimmed) }
    }

    /// Every item belonging to one product, matched on its normalised name key.
    /// Used by CheckStockIntent to total a product across all its locations.
    static func items(productID: String) -> [Item] {
        allItems().filter { ProductEntity.normalise($0.name) == productID }
    }

    /// Every location in the store.
    static func allLocations() -> [Location] {
        (try? context.fetch(FetchDescriptor<Location>())) ?? []
    }

    /// The live Location for an entity id, or nil if it has since been deleted.
    static func location(id: UUID) -> Location? {
        allLocations().first { $0.id == id }
    }

    /// Every item stored in `location` or any space nested inside it.
    /// Cycle-safe via the shared selfAndDescendantIDs walk.
    static func items(inSubtreeOf location: Location) -> [Item] {
        let subtree = location.selfAndDescendantIDs
        return allItems().filter { item in
            guard let home = item.location else { return false }
            return subtree.contains(home.id)
        }
    }

    /// Everything on the Restock list — the same definition RestockTab shows.
    static func restockItems() -> [Item] {
        allItems().filter(\.needsRestock)
    }

    /// Persists pending changes. SwiftData autosaves in-app, but an intent that
    /// runs in a background process should not rely on that timing.
    static func save() {
        try? context.save()
    }
}
