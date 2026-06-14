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

    @Property(title: "Name")
    var name: String

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

// MARK: - Query

struct ProductEntityQuery: EntityStringQuery {

    @MainActor
    func entities(for identifiers: [String]) async throws -> [ProductEntity] {
        let wanted = Set(identifiers)
        return distinctProducts().filter { wanted.contains($0.id) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [ProductEntity] {
        let query = string.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        return distinctProducts().filter { $0.name.localizedStandardContains(query) }
    }

    @MainActor
    func suggestedEntities() async throws -> [ProductEntity] {
        distinctProducts()
    }

    /// One ProductEntity per distinct item name in the store, keyed by the
    /// normalised name and labelled with the first spelling encountered.
    @MainActor
    private func distinctProducts() -> [ProductEntity] {
        var displayNameByKey: [String: String] = [:]
        for item in IntentStore.allItems() {
            let key = ProductEntity.normalise(item.name)
            guard !key.isEmpty else { continue }
            if displayNameByKey[key] == nil { displayNameByKey[key] = item.name }
        }
        return displayNameByKey
            .map { ProductEntity(id: $0.key, name: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

extension ProductEntity {
    /// Normalises a name into its product key.
    static func normalise(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces).lowercased()
    }
}
