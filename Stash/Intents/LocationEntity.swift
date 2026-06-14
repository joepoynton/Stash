//
//  LocationEntity.swift
//  Stash
//
//  An AppEntity snapshot of a Location (an Area or any Space within it),
//  exposed to Siri, Shortcuts and Spotlight. Like ItemEntity it is a value
//  snapshot keyed by the Location's stable UUID.
//

import Foundation
import AppIntents
import CoreSpotlight
import UniformTypeIdentifiers
import SwiftData

struct LocationEntity: AppEntity, IndexedEntity {

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Space")

    static let defaultQuery = LocationEntityQuery()

    let id: UUID

    @Property(title: "Name")
    var name: String

    /// Full breadcrumb to and including this location, e.g. "Garage › Top Shelf".
    @Property(title: "Path")
    var path: String

    /// The breadcrumb of ancestors only (empty for a root Area). Used as the
    /// display subtitle so it doesn't repeat the name shown in the title.
    var parentPath: String

    init(location: Location) {
        // Plain stored properties first, then the @Property-wrapped ones, so the
        // wrappers' definite-initialization analysis sees a fully-formed self.
        self.id = location.id
        self.parentPath = location.ancestorChain.dropLast().map(\.name).joined(separator: " › ")
        self.name = location.name
        self.path = location.pathString
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: parentPath.isEmpty ? "Area" : "\(parentPath)"
        )
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .item)
        attributes.title = name
        attributes.contentDescription = parentPath.isEmpty ? "Area" : parentPath
        attributes.keywords = [name, "Stash", "location"]
        return attributes
    }
}

// MARK: - Query

struct LocationEntityQuery: EntityStringQuery {

    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [LocationEntity] {
        let wanted = Set(identifiers)
        return try fetchLocations { wanted.contains($0.id) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [LocationEntity] {
        let query = string.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        return try fetchLocations { $0.name.localizedStandardContains(query) }
    }

    @MainActor
    func suggestedEntities() async throws -> [LocationEntity] {
        try fetchLocations { _ in true }
    }

    @MainActor
    private func fetchLocations(_ isIncluded: (Location) -> Bool) throws -> [LocationEntity] {
        let context = StashModelContainer.shared.mainContext
        let all = try context.fetch(FetchDescriptor<Location>())
        return all
            .filter(isIncluded)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map(LocationEntity.init)
    }
}
