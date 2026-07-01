//
//  Location+Ancestry.swift
//  Stash
//
//  Single home for all ancestor-walking and tree-mutation logic.
//  Every walk here is cycle-safe: bounded by maxAncestorDepth and a
//  visited-set, so a corrupted parent cycle (possible via CloudKit
//  merge) can never hang or crash the app.
//

import Foundation
import SwiftData
import os

extension Location {

    /// Hard ceiling on ancestor-chain length. Real trees are a handful of
    /// levels deep; anything approaching this is corrupt data.
    static let maxAncestorDepth = 50

    /// The chain from the root Area down to this location, inclusive.
    /// e.g. [Garage, Top Shelf, Red Box]. Stops early on a repeated node
    /// or at maxAncestorDepth, so a parent cycle yields a truncated chain
    /// instead of an infinite loop.
    var ancestorChain: [Location] {
        var chain: [Location] = []
        var seen = Set<UUID>()
        var current: Location? = self
        while let loc = current, chain.count < Self.maxAncestorDepth,
              seen.insert(loc.id).inserted {
            chain.insert(loc, at: 0)
            current = loc.parent
        }
        return chain
    }

    /// Full breadcrumb path from root to here, e.g. "Garage › Top Shelf".
    var pathString: String {
        ancestorChain.map(\.name).joined(separator: " › ")
    }

    /// The root Area at the top of this location's tree (self if root).
    var rootAncestor: Location {
        ancestorChain.first ?? self
    }

    /// This location's id plus every descendant id. Cycle-safe (a visited-set
    /// bounds a corrupted parent/child cycle). Used to exclude a whole subtree
    /// from a "Move to…" destination picker so a space can't be moved inside
    /// itself or any of its own descendants.
    var selfAndDescendantIDs: Set<UUID> {
        var ids = Set<UUID>()
        var stack: [Location] = [self]
        while let loc = stack.popLast() {
            guard ids.insert(loc.id).inserted else { continue }
            stack.append(contentsOf: loc.childList)
        }
        return ids
    }
}

// MARK: - Cycle repair

extension Location {

    private static let repairLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Poynt.Stash",
        category: "DataRepair"
    )

    /// Launch-time safety pass: walks every location's ancestry and severs
    /// any parent cycle by promoting the self-ancestor location to a root
    /// Area. Returns the number of locations repaired.
    @discardableResult
    static func repairCycles(in context: ModelContext) -> Int {
        guard let locations = try? context.fetch(FetchDescriptor<Location>()) else { return 0 }
        var repaired = 0
        for location in locations {
            var seen: Set<UUID> = [location.id]
            var current = location.parent
            var depth = 0
            while let ancestor = current, depth < maxAncestorDepth {
                if ancestor.id == location.id {
                    repairLogger.warning("Cycle detected: \"\(location.name, privacy: .public)\" was its own ancestor. Severed parent link and promoted it to a root Area.")
                    location.parent = nil
                    repaired += 1
                    break
                }
                // A repeat that isn't us means the cycle sits higher up the
                // chain; the loop iteration for that location will sever it.
                guard seen.insert(ancestor.id).inserted else { break }
                current = ancestor.parent
                depth += 1
            }
        }
        if repaired > 0 {
            try? context.save()
        }
        return repaired
    }
}

// MARK: - Tree mutation helpers

extension ModelContext {

    /// Deletes a location and everything beneath it. Iterative with a
    /// visited-set so a corrupted parent/child cycle cannot recurse forever.
    func cascadeDelete(_ location: Location) {
        var visited = Set<UUID>()
        var stack: [Location] = [location]
        while let loc = stack.popLast() {
            guard visited.insert(loc.id).inserted else { continue }
            stack.append(contentsOf: loc.childList)
            delete(loc)
        }
    }
}

extension Location {

    static let unsortedAreaName = "Unsorted"

    /// The root Area used as a safety net for items that would otherwise
    /// have no location. Reuses an existing root "Unsorted" Area if present;
    /// creates one otherwise. `excluding` prevents matching the Area that is
    /// currently being deleted (whose items relationship is cascade).
    static func unsortedArea(in context: ModelContext, excluding excludedID: UUID? = nil) -> Location {
        let all = (try? context.fetch(FetchDescriptor<Location>())) ?? []
        if let existing = all.first(where: {
            $0.parent == nil && $0.name == unsortedAreaName && $0.id != excludedID
        }) {
            return existing
        }
        let area = Location(name: unsortedAreaName, icon: "tray.fill")
        context.insert(area)
        return area
    }
}
