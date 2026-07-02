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
//  The @Property surface is deliberately broad. These typed properties are
//  what the system's semantic index and Apple Intelligence read to answer
//  contextual questions ("what's expiring soon", "what's in the garage",
//  "what am I low on") — and on iOS 18 they already power the auto-generated
//  "Find Items" action in Shortcuts via ItemEntityQuery's EntityPropertyQuery
//  conformance below.
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

    // Plain stored properties, assigned FIRST in init — the @Property wrappers'
    // definite-initialization analysis needs the plain ones settled before any
    // wrapped assignment. Not surfaced as @Properties: photo bytes belong in
    // display representations / Spotlight thumbnails, and the note reads best
    // folded into dialogue rather than as a bare filterable field.
    var photoData: Data?
    var outOfPlaceNote: String?

    @Property(title: "Name")
    var name: String

    /// Full breadcrumb to the item's home, e.g. "Garage › Top Shelf".
    @Property(title: "Location")
    var locationPath: String

    /// The immediate space the item lives in, e.g. "Top Shelf".
    @Property(title: "Space")
    var spaceName: String

    /// The root Area at the top of the item's tree, e.g. "Garage".
    @Property(title: "Area")
    var areaName: String

    /// Stock as a phrase, e.g. "3 cans", or "Not tracked".
    @Property(title: "Stock")
    var quantitySummary: String

    @Property(title: "Quantity")
    var quantity: Int?

    @Property(title: "Minimum Quantity")
    var minimumQuantity: Int?

    @Property(title: "Unit")
    var unit: String?

    @Property(title: "Notes")
    var notes: String?

    @Property(title: "Out of Place")
    var isOutOfPlace: Bool

    @Property(title: "Low Stock")
    var isLowStock: Bool

    @Property(title: "On Order")
    var isOnOrder: Bool

    @Property(title: "Needs Restocking")
    var needsRestock: Bool

    @Property(title: "Expiry Date")
    var expiryDate: Date?

    @Property(title: "Expired")
    var isExpired: Bool

    @Property(title: "Date Added")
    var dateAdded: Date

    @Property(title: "Last Verified")
    var lastVerified: Date

    init(item: Item) {
        self.id = item.id
        self.photoData = item.photo
        self.outOfPlaceNote = item.outOfPlaceNote

        let chain = item.location?.ancestorChain ?? []
        self.name = item.name
        self.locationPath = item.location?.pathString ?? "No location"
        self.spaceName = item.location?.name ?? ""
        self.areaName = chain.first?.name ?? ""
        self.quantitySummary = IntentFormatting.stockSummary(quantity: item.quantity, unit: item.unit)
        self.quantity = item.quantity
        self.minimumQuantity = item.minimumQuantity
        self.unit = item.unit
        self.notes = item.notes
        self.isOutOfPlace = item.isOutOfPlace
        self.isLowStock = item.isLowStock
        self.isOnOrder = item.isOnOrder
        self.needsRestock = item.needsRestock
        self.expiryDate = item.expiryDate
        self.isExpired = item.isExpired
        self.dateAdded = item.dateAdded
        self.lastVerified = item.lastVerified
    }

    /// Title + breadcrumb + photo. The subtitle and image are what make the
    /// system's disambiguation UI usable when the same product lives in
    /// several places ("AA Batteries — Garage › Shelf" vs "… — Kitchen").
    var displayRepresentation: DisplayRepresentation {
        var subtitle = locationPath
        if quantity != nil {
            subtitle += " · \(quantitySummary)"
        }
        if let photoData {
            return DisplayRepresentation(
                title: "\(name)",
                subtitle: "\(subtitle)",
                image: DisplayRepresentation.Image(data: photoData)
            )
        }
        return DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(subtitle)"
        )
    }

    /// Enriches the default Spotlight record so the semantic index has real
    /// signal: breadcrumb + stock + status in the snippet, expiry as a due
    /// date, name/path tokens as keywords, and the photo as the thumbnail.
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .item)
        attributes.title = name
        attributes.displayName = name

        var parts = [locationPath]
        if quantity != nil {
            parts.append(quantitySummary)
        }
        if isOutOfPlace {
            parts.append(outOfPlaceNote.map { "Out of place: \($0)" } ?? "Out of place")
        }
        if needsRestock {
            parts.append(isOnOrder ? "On order" : "Needs restocking")
        }
        if let expiryDate {
            let day = expiryDate.formatted(date: .abbreviated, time: .omitted)
            parts.append(isExpired ? "Expired \(day)" : "Expires \(day)")
        }
        attributes.contentDescription = parts.joined(separator: " · ")

        var keywords = IntentMatching.tokens(name)
        keywords.append(contentsOf: locationPath.components(separatedBy: " › "))
        keywords.append(contentsOf: ["Stash", "inventory"])
        attributes.keywords = keywords

        if let notes, !notes.isEmpty {
            attributes.textContent = notes
        }
        attributes.thumbnailData = photoData
        attributes.dueDate = expiryDate
        attributes.addedDate = dateAdded
        attributes.contentModificationDate = lastVerified
        return attributes
    }
}

// MARK: - Query

/// Backs ItemEntity resolution against the shared SwiftData store.
///
/// - EntityStringQuery powers "where is my <spoken name>", with ranked fuzzy
///   matching (see IntentMatching) so plural/singular and partial names hit.
/// - EnumerableEntityQuery lets the system and Shortcuts enumerate the whole
///   inventory (small by design — free tier is capped).
/// - EntityPropertyQuery generates the system "Find Items" action: filter by
///   expiry, stock state, area etc., sorted, with a limit — the structured
///   query shape Apple Intelligence targets for contextual questions.
struct ItemEntityQuery: EntityStringQuery, EnumerableEntityQuery, EntityPropertyQuery {

    /// Fetch specific items by id (e.g. re-resolving a previously chosen item).
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [ItemEntity] {
        let wanted = Set(identifiers)
        return try fetchItems { wanted.contains($0.id) }
    }

    /// String search used when the user names an item by voice or text.
    /// Ranked: exact name → prefix → contains → token/stem match, then
    /// location-path and notes matches after any name match.
    @MainActor
    func entities(matching string: String) async throws -> [ItemEntity] {
        let query = string.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        let all = (try? IntentStore.context.fetch(FetchDescriptor<Item>())) ?? []
        return IntentMatching.rankedMatches(
            query: query,
            candidates: all,
            name: { $0.name },
            secondary: { "\($0.location?.pathString ?? "") \($0.notes ?? "")" }
        )
        .map(ItemEntity.init)
    }

    /// Items offered as suggestions in the Shortcuts editor and to Siri.
    /// Recently viewed items lead (same source as Home's Recents), the rest
    /// follow alphabetically.
    @MainActor
    func suggestedEntities() async throws -> [ItemEntity] {
        let all = try fetchItems { _ in true }
        let recentIDs = RecentlyAccessedStore().orderedIDs
        guard !recentIDs.isEmpty else { return all }

        var leading: [ItemEntity] = []
        for idString in recentIDs {
            if let match = all.first(where: { $0.id.uuidString == idString }) {
                leading.append(match)
            }
        }
        let leadingIDs = Set(leading.map(\.id))
        return leading + all.filter { !leadingIDs.contains($0.id) }
    }

    /// Full enumeration for the system. Inventories are small by design.
    @MainActor
    func allEntities() async throws -> [ItemEntity] {
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

    // MARK: EntityPropertyQuery ("Find Items")

    // Explicitly optional: the requirement is IntentDescription?, and both
    // EnumerableEntityQuery and EntityPropertyQuery declare it — a concrete
    // witness must match exactly to satisfy both at once.
    static let findIntentDescription: IntentDescription? = IntentDescription(
        "Find items in your Stash inventory by name, place, expiry, or stock state.",
        categoryName: "Stash"
    )

    static let properties = QueryProperties {
        Property(\ItemEntity.$name) {
            EqualToComparator { value in
                ItemEntityMatcher { $0.name.localizedCaseInsensitiveCompare(value) == .orderedSame }
            }
            ContainsComparator { value in
                ItemEntityMatcher { IntentMatching.matches(query: value, candidate: $0.name) }
            }
        }
        Property(\ItemEntity.$areaName) {
            EqualToComparator { value in
                ItemEntityMatcher { $0.areaName.localizedCaseInsensitiveCompare(value) == .orderedSame }
            }
            ContainsComparator { value in
                ItemEntityMatcher { IntentMatching.matches(query: value, candidate: $0.areaName) }
            }
        }
        Property(\ItemEntity.$spaceName) {
            ContainsComparator { value in
                ItemEntityMatcher { IntentMatching.matches(query: value, candidate: $0.spaceName) }
            }
        }
        Property(\ItemEntity.$isLowStock) {
            EqualToComparator { value in ItemEntityMatcher { $0.isLowStock == value } }
        }
        Property(\ItemEntity.$needsRestock) {
            EqualToComparator { value in ItemEntityMatcher { $0.needsRestock == value } }
        }
        Property(\ItemEntity.$isOutOfPlace) {
            EqualToComparator { value in ItemEntityMatcher { $0.isOutOfPlace == value } }
        }
        Property(\ItemEntity.$isExpired) {
            EqualToComparator { value in ItemEntityMatcher { $0.isExpired == value } }
        }
        Property(\ItemEntity.$expiryDate) {
            LessThanComparator { date in
                ItemEntityMatcher { ($0.expiryDate ?? .distantFuture) < date }
            }
            GreaterThanComparator { date in
                ItemEntityMatcher { ($0.expiryDate ?? .distantPast) > date }
            }
            IsBetweenComparator { lower, upper in
                ItemEntityMatcher { entity in
                    guard let expiry = entity.expiryDate else { return false }
                    return expiry >= lower && expiry <= upper
                }
            }
        }
    }

    static let sortingOptions = SortingOptions {
        SortableBy(\ItemEntity.$name)
        SortableBy(\ItemEntity.$dateAdded)
        SortableBy(\ItemEntity.$lastVerified)
    }

    @MainActor
    func entities(
        matching comparators: [ItemEntityMatcher],
        mode: ComparatorMode,
        sortedBy: [EntityQuerySort<ItemEntity>],
        limit: Int?
    ) async throws -> [ItemEntity] {
        var results = try fetchItems { _ in true }.filter { entity in
            switch mode {
            case .and: return comparators.allSatisfy { $0.matches(entity) }
            case .or:  return comparators.contains { $0.matches(entity) }
            }
        }

        for sort in sortedBy.reversed() {
            let order: SortOrder = (sort.order == .ascending) ? .forward : .reverse
            switch sort.by {
            case \ItemEntity.$name:
                results.sort(using: KeyPathComparator(\ItemEntity.name, order: order))
            case \ItemEntity.$dateAdded:
                results.sort(using: KeyPathComparator(\ItemEntity.dateAdded, order: order))
            case \ItemEntity.$lastVerified:
                results.sort(using: KeyPathComparator(\ItemEntity.lastVerified, order: order))
            default:
                break
            }
        }

        if let limit, results.count > limit {
            results = Array(results.prefix(limit))
        }
        return results
    }
}

/// The comparator mapping type for ItemEntityQuery's EntityPropertyQuery:
/// each system comparator becomes a plain closure over the entity snapshot,
/// evaluated in-memory (same full-fetch strategy as everything else here).
struct ItemEntityMatcher {
    let matches: (ItemEntity) -> Bool
}
