//
//  ItemEntity.swift
//  Stash
//
//  An AppEntity snapshot of an Item, exposed to Siri, Shortcuts and Spotlight.
//
//  AppEntities are value-type snapshots, not live SwiftData objects: an intent
//  can be resolved in a background process, so we copy the fields we need out
//  of the Item at query time and keep only its `id` (the Item's stable UUID)
//  as the bridge back to the store.
//
//  Conforming to IndexedEntity lets the same type be pushed into the on-device
//  Spotlight index (see SpotlightIndexer) so items surface in system-wide
//  search with attribution back to Stash.
//

import Foundation
import AppIntents
import CoreSpotlight
import UniformTypeIdentifiers
import SwiftData

struct ItemEntity: AppEntity, IndexedEntity {

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Item")

    static let defaultQuery = ItemEntityQuery()

    /// The backing Item's UUID — stable across launches and CloudKit syncs.
    let id: UUID

    @Property(title: "Name")
    var name: String

    /// Full breadcrumb to the item's home, e.g. "Garage › Top Shelf".
    @Property(title: "Location")
    var locationPath: String

    /// Stock as a phrase, e.g. "3 cans", or "Not tracked".
    @Property(title: "Quantity")
    var quantitySummary: String

    @Property(title: "Out of Place")
    var isOutOfPlace: Bool

    // Raw values retained for building natural dialogue in the intents. Not
    // surfaced as system @Properties — quantitySummary already covers display.
    var quantity: Int?
    var unit: String?
    var outOfPlaceNote: String?

    init(item: Item) {
        self.id = item.id
        self.name = item.name
        self.locationPath = item.location?.pathString ?? "No location"
        self.quantity = item.quantity
        self.unit = item.unit
        self.isOutOfPlace = item.isOutOfPlace
        self.outOfPlaceNote = item.outOfPlaceNote
        self.quantitySummary = IntentFormatting.stockSummary(quantity: item.quantity, unit: item.unit)
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(locationPath)"
        )
    }

    /// Enriches the default Spotlight record with the location path and stock
    /// so the snippet is useful in system search.
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .item)
        attributes.title = name
        var description = locationPath
        if quantity != nil {
            description += " · \(quantitySummary)"
        }
        if isOutOfPlace {
            description += " · Out of place"
        }
        attributes.contentDescription = description
        attributes.keywords = [name, "Stash", "inventory"]
        return attributes
    }
}

// MARK: - Query

/// Backs ItemEntity resolution against the shared SwiftData store. As an
/// EntityStringQuery it can both fetch entities by id and search them by a
/// spoken / typed string, which is what powers "where is my <item>".
struct ItemEntityQuery: EntityStringQuery {

    /// Fetch specific items by id (e.g. re-resolving a previously chosen item).
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [ItemEntity] {
        let wanted = Set(identifiers)
        return try fetchItems { wanted.contains($0.id) }
    }

    /// String search used when the user names an item by voice or text.
    /// Matches names case- and diacritic-insensitively, mirroring in-app search.
    @MainActor
    func entities(matching string: String) async throws -> [ItemEntity] {
        let query = string.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        return try fetchItems { $0.name.localizedStandardContains(query) }
    }

    /// Items offered as suggestions in the Shortcuts editor.
    @MainActor
    func suggestedEntities() async throws -> [ItemEntity] {
        try fetchItems { _ in true }
    }

    /// Shared fetch: pulls all items once, applies the predicate on the
    /// MainActor, and returns sorted value snapshots. Inventory sizes are
    /// small, so a full fetch + in-memory filter is simplest and robust against
    /// SwiftData predicate limitations around UUID-array membership.
    @MainActor
    private func fetchItems(_ isIncluded: (Item) -> Bool) throws -> [ItemEntity] {
        let context = StashModelContainer.shared.mainContext
        let all = try context.fetch(FetchDescriptor<Item>())
        return all
            .filter(isIncluded)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map(ItemEntity.init)
    }
}
