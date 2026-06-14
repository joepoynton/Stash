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

    /// Persists pending changes. SwiftData autosaves in-app, but an intent that
    /// runs in a background process should not rely on that timing.
    static func save() {
        try? context.save()
    }
}
