//
//  ImportWriter.swift
//  Stash
//
//  1.3 spreadsheet import (spec B8). Applies an ImportPlan to the store:
//  creates the new spaces parent-first, inserts the items, and saves once.
//  Main actor, because it touches the ModelContext.
//
//  Spotlight reindexing happens by itself through the existing didSave observer.
//

import Foundation
import SwiftData

enum ImportWriter {

    enum WriteError: LocalizedError {
        case missingLocation

        var errorDescription: String? {
            switch self {
            case .missingLocation:
                return "A space the import needed no longer exists."
            }
        }
    }

    /// Copies the existing tree into plain values for the planner. Built on
    /// the main actor; the planner itself then runs off it.
    static func snapshot(of locations: [Location]) -> ImportTreeSnapshot {
        ImportTreeSnapshot(nodes: locations.map { location in
            ImportTreeSnapshot.Node(
                id: location.id,
                name: location.name,
                parentID: location.parent?.id,
                dateCreated: location.dateCreated,
                itemNames: location.itemList.map(\.name)
            )
        })
    }

    /// Writes the plan. All or nothing: on any failure the context is rolled
    /// back and the error is thrown, so "Nothing was imported" is true.
    static func apply(_ plan: ImportPlan, in context: ModelContext, calendar: Calendar = .current) throws {
        do {
            let existing = try context.fetch(FetchDescriptor<Location>())
            let existingByID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

            // New spaces, parent-first (the plan guarantees the order).
            var created: [Location] = []
            func resolve(_ ref: ImportPlan.LocationRef?) throws -> Location? {
                switch ref {
                case nil:
                    return nil
                case .existing(let id)?:
                    guard let location = existingByID[id] else { throw WriteError.missingLocation }
                    return location
                case .new(let index)?:
                    guard created.indices.contains(index) else { throw WriteError.missingLocation }
                    return created[index]
                }
            }

            for planned in plan.newLocations {
                if planned.isUnsortedArea {
                    // Reuses an "Unsorted" Area if one exists, else makes it
                    // with the usual tray icon.
                    created.append(Location.unsortedArea(in: context))
                    continue
                }
                let parent = try resolve(planned.parent)
                // Same defaults as creating an Area by hand (AddLocationSheet):
                // the archive-box icon for a top-level Area, no colour.
                let location = Location(
                    name: planned.name,
                    icon: parent == nil ? "archivebox.fill" : nil,
                    color: nil,
                    parent: parent
                )
                context.insert(location)
                created.append(location)
            }

            for planned in plan.items {
                let item = Item(name: planned.name, location: try resolve(planned.target))
                item.notes = planned.notes
                item.quantity = planned.quantity
                item.unit = planned.unit
                item.minimumQuantity = planned.minimum
                item.expiryDate = planned.expiry?.date(in: calendar)
                // Same as the JSON import: new items default to "always verified".
                item.neverStale = true
                context.insert(item)
            }

            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
