//
//  ProductEntity.swift
//  Stash
//
//  A "product" is an item considered across every location it lives in — all
//  the "AA Batteries" in the house, regardless of which drawer each pack is in.
//  CheckStockIntent uses this granularity so "how many batteries do I have"
//  resolves to a single product (no spurious which-drawer prompt) and totals
//  the stock across locations.
//
//  This is deliberately distinct from ItemEntity, which is per-location: Find
//  and Use *want* to disambiguate between the same product in different places.
//
//  Identity is the case-/whitespace-normalised name, so the same product name
//  in several locations collapses to one entity.
//

import Foundation
import AppIntents
import SwiftData

struct ProductEntity: AppEntity {

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Item")

    static let defaultQuery = ProductEntityQuery()

    /// Normalised name (trimmed + lowercased) — the product's stable key.
    let id: String

    /// Total tracked stock across every location, e.g. "6 cans and 2 boxes".
    /// Nil when quantity tracking is off everywhere.
    var stockSummary: String?

    /// How many distinct locations hold this product.
    var locationCount: Int

    @Property(title: "Name")
    var name: String

    init(id: String, name: String, stockSummary: String? = nil, locationCount: Int = 0) {
        self.id = id
        self.stockSummary = stockSummary
        self.locationCount = locationCount
        self.name = name
    }

    var displayRepresentation: DisplayRepresentation {
        var parts: [String] = []
        if let stockSummary {
            parts.append(stockSummary)
        }
        if locationCount > 1 {
            parts.append("in \(locationCount) places")
        }
        guard !parts.isEmpty else {
            return DisplayRepresentation(title: "\(name)")
        }
        return DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(parts.joined(separator: " · "))"
        )
    }
}

// MARK: - Query

struct ProductEntityQuery: EntityStringQuery {

    @MainActor
    func entities(for identifiers: [String]) async throws -> [ProductEntity] {
        let wanted = Set(identifiers)
        return distinctProducts().filter { wanted.contains($0.id) }
    }

    /// Fuzzy stem matching so "batteries" resolves the "AA Battery" product
    /// and vice versa — the single most common miss for spoken stock checks.
    @MainActor
    func entities(matching string: String) async throws -> [ProductEntity] {
        let query = string.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        return IntentMatching.rankedMatches(
            query: query,
            candidates: distinctProducts(),
            name: { $0.name }
        )
    }

    @MainActor
    func suggestedEntities() async throws -> [ProductEntity] {
        distinctProducts()
    }

    /// One ProductEntity per distinct item name in the store, keyed by the
    /// normalised name, labelled with the first spelling encountered, and
    /// carrying its cross-location totals for the disambiguation subtitle.
    @MainActor
    private func distinctProducts() -> [ProductEntity] {
        var itemsByKey: [String: [Item]] = [:]
        var keyOrder: [String] = []
        for item in IntentStore.allItems() {
            let key = ProductEntity.normalise(item.name)
            guard !key.isEmpty else { continue }
            if itemsByKey[key] == nil { keyOrder.append(key) }
            itemsByKey[key, default: []].append(item)
        }
        return keyOrder
            .compactMap { key -> ProductEntity? in
                guard let items = itemsByKey[key], let first = items.first else { return nil }
                return ProductEntity(
                    id: key,
                    name: first.name,
                    stockSummary: IntentFormatting.totalStockPhrase(for: items),
                    locationCount: Set(items.compactMap { $0.location?.id }).count
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

extension ProductEntity {
    /// Normalises a name into its product key.
    static func normalise(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces).lowercased()
    }
}
