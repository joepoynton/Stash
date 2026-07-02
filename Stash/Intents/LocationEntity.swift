//
//  LocationEntity.swift
//  Stash
//
//  An AppEntity snapshot of a Location (an Area or any Space within it),
//  exposed to Siri, Shortcuts and Spotlight. Like ItemEntity it is a value
//  snapshot keyed by the Location's stable UUID.
//
//  The Spotlight record carries the names of the items stored inside, so a
//  system search for "batteries" can surface "Garage › Shelf" as well as the
//  items themselves — which is how the semantic index learns what lives where.
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

    // Plain stored properties first (see ItemEntity for the init-order note).
    /// The breadcrumb of ancestors only (empty for a root Area). Used as the
    /// display subtitle so it doesn't repeat the name shown in the title.
    var parentPath: String
    var photoData: Data?
    var iconName: String?
    /// Names of the items stored directly in this space (capped) — Spotlight
    /// keyword fodder.
    var containedItemNames: [String]

    @Property(title: "Name")
    var name: String

    /// Full breadcrumb to and including this location, e.g. "Garage › Top Shelf".
    @Property(title: "Path")
    var path: String

    /// The root Area this space belongs to (itself, for an Area).
    @Property(title: "Area")
    var areaName: String

    @Property(title: "Items")
    var itemCount: Int

    @Property(title: "Spaces Inside")
    var spaceCount: Int

    @Property(title: "Is an Area")
    var isArea: Bool

    init(location: Location) {
        self.id = location.id
        let chain = location.ancestorChain
        self.parentPath = chain.dropLast().map(\.name).joined(separator: " › ")
        self.photoData = location.photo
        self.iconName = location.icon
        self.containedItemNames = location.itemList.map(\.name)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .prefix(30).map { $0 }

        self.name = location.name
        self.path = location.pathString
        self.areaName = chain.first?.name ?? location.name
        self.itemCount = location.itemList.count
        self.spaceCount = location.childList.count
        self.isArea = location.isRoot
    }

    var displayRepresentation: DisplayRepresentation {
        let subtitle = parentPath.isEmpty ? "Area" : parentPath
        if let photoData {
            return DisplayRepresentation(
                title: "\(name)",
                subtitle: "\(subtitle)",
                image: DisplayRepresentation.Image(data: photoData)
            )
        }
        if let iconName {
            return DisplayRepresentation(
                title: "\(name)",
                subtitle: "\(subtitle)",
                image: DisplayRepresentation.Image(systemName: iconName)
            )
        }
        return DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(subtitle)"
        )
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .item)
        attributes.title = name
        attributes.displayName = name

        var parts = [parentPath.isEmpty ? "Area" : parentPath]
        var counts: [String] = []
        if itemCount > 0 {
            counts.append(itemCount == 1 ? "1 item" : "\(itemCount) items")
        }
        if spaceCount > 0 {
            counts.append(spaceCount == 1 ? "1 space" : "\(spaceCount) spaces")
        }
        if !counts.isEmpty {
            parts.append(counts.joined(separator: ", "))
        }
        if !containedItemNames.isEmpty {
            parts.append("Contains \(containedItemNames.prefix(5).joined(separator: ", "))")
        }
        attributes.contentDescription = parts.joined(separator: " · ")

        var keywords = IntentMatching.tokens(name)
        keywords.append(contentsOf: path.components(separatedBy: " › "))
        keywords.append(contentsOf: containedItemNames)
        keywords.append(contentsOf: ["Stash", "location"])
        attributes.keywords = keywords
        attributes.thumbnailData = photoData
        return attributes
    }
}

// MARK: - Query

struct LocationEntityQuery: EntityStringQuery, EnumerableEntityQuery {

    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [LocationEntity] {
        let wanted = Set(identifiers)
        return try fetchLocations { wanted.contains($0.id) }
    }

    /// Ranked fuzzy matching on the name, falling back to the breadcrumb so
    /// "garage shelf" resolves even though the space is just named "Shelf".
    @MainActor
    func entities(matching string: String) async throws -> [LocationEntity] {
        let query = string.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        let all = (try? IntentStore.context.fetch(FetchDescriptor<Location>())) ?? []
        return IntentMatching.rankedMatches(
            query: query,
            candidates: all,
            name: { $0.name },
            secondary: { $0.pathString }
        )
        .map(LocationEntity.init)
    }

    /// Areas first (they're what people name in speech), then nested spaces.
    @MainActor
    func suggestedEntities() async throws -> [LocationEntity] {
        let all = try fetchLocations { _ in true }
        return all.filter(\.isArea) + all.filter { !$0.isArea }
    }

    @MainActor
    func allEntities() async throws -> [LocationEntity] {
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
