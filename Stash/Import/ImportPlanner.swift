//
//  ImportPlanner.swift
//  Stash
//
//  1.3 spreadsheet import (spec B5, B7, B8). Works out everything an import
//  would do (spaces to create, items to add, rows to skip and why) without
//  writing anything. The preview screen shows the plan; ImportWriter applies it.
//
//  Pure: no SwiftData. The existing tree arrives as a plain-struct snapshot
//  built on the main actor, so planning can run off it. Foundation only and
//  `nonisolated` throughout.
//

import Foundation

// MARK: - Inputs

/// The existing locations and item names, copied into plain values.
nonisolated struct ImportTreeSnapshot: Sendable {
    nonisolated struct Node: Sendable {
        var id: UUID
        var name: String
        /// Nil for a top-level Area.
        var parentID: UUID?
        var dateCreated: Date
        /// Names of the items directly in this location.
        var itemNames: [String]

        init(id: UUID, name: String, parentID: UUID?, dateCreated: Date, itemNames: [String] = []) {
            self.id = id
            self.name = name
            self.parentID = parentID
            self.dateCreated = dateCreated
            self.itemNames = itemNames
        }
    }

    var nodes: [Node]

    init(nodes: [Node] = []) {
        self.nodes = nodes
    }
}

nonisolated enum ImportDestination: Sendable, Equatable {
    /// The first part of each path becomes (or matches) a top-level Area.
    case topLevel
    /// Every path is created beneath this existing location.
    case location(UUID)
}

nonisolated struct ImportOptions: Sendable {
    var destination: ImportDestination = .topLevel
    /// "Blank location means same as the row above."
    var fillDown = true
    var skipDuplicates = true
    /// Set when the user flips the date-order toggle; nil lets the column decide.
    var dateOrder: ImportDateOrder? = nil
    /// Used when nothing in the date column settles the order. The caller
    /// derives it from the device's region.
    var regionDateOrder: ImportDateOrder = .dayFirst
    /// How many more items a free user may add. Nil for Pro (no limit).
    var remainingFreeCapacity: Int? = nil
    /// Where rows with no location go when importing to the top level.
    /// Matches `Location.unsortedAreaName`.
    var unsortedAreaName = "Unsorted"

    init() {}
}

// MARK: - Plan

nonisolated struct ImportPlan: Sendable {

    /// A location the plan refers to: one that already exists, or one of
    /// `newLocations` by its position in that array.
    nonisolated enum LocationRef: Hashable, Sendable {
        case existing(UUID)
        case new(Int)
    }

    nonisolated struct NewLocation: Sendable, Equatable {
        var name: String
        /// Nil for a new top-level Area. A `.new` parent always comes earlier
        /// in `newLocations`, so creating them in order is parent-first.
        var parent: LocationRef?
        /// Full path from the top level, for display.
        var path: [String]
        /// The catch-all Area for rows with no location. The writer creates it
        /// with `Location.unsortedArea(in:)` so it gets the usual icon.
        var isUnsortedArea: Bool
    }

    nonisolated struct PlannedItem: Sendable, Equatable {
        /// 1-based position among the spreadsheet's non-blank rows.
        var row: Int
        var name: String
        var target: LocationRef
        /// Full path of the target from the top level, for display.
        var path: [String]
        var quantity: Int?
        var unit: String?
        var minimum: Int?
        var expiry: ImportDay?
        var notes: String?
    }

    nonisolated enum SkipReason: Sendable, Equatable {
        case noName
        /// Same name as an item already in that space.
        case alreadyExists
        /// An exact copy of an earlier row in this file (every cell the same).
        /// Rows that share a name but differ anywhere else, such as two
        /// "Titanium White" paints from different brands, are both kept.
        case repeatedInFile
        case freeLimit
    }

    nonisolated struct SkippedRow: Sendable, Equatable {
        var row: Int
        var name: String
        var reason: SkipReason
    }

    /// Spaces to create, parent-first.
    var newLocations: [NewLocation] = []
    var items: [PlannedItem] = []
    var skipped: [SkippedRow] = []

    /// Every space on the path of an item being added (below the chosen
    /// destination), new or not. "Add 46 items in 9 spaces (4 new)".
    var spaceCount = 0
    /// Spaces that items land in directly.
    var targetSpaceCount = 0

    /// Present when a date column is mapped.
    var dateOrder: ImportDateOrderDecision?
    /// Whether the fill-down toggle is worth showing: a location column has
    /// blanks following non-blanks.
    var fillDownApplies = false

    var unreadableQuantityCount = 0
    var unreadableExpiryCount = 0
    var ignoredMinimumCount = 0

    // MARK: Counts

    var newSpaceCount: Int { newLocations.count }

    func skipCount(_ reason: SkipReason) -> Int {
        skipped.reduce(0) { $0 + ($1.reason == reason ? 1 : 0) }
    }

    var duplicateCount: Int { skipCount(.alreadyExists) + skipCount(.repeatedInFile) }

    /// The Import button is disabled when nothing would be added.
    var hasAnythingToImport: Bool { !items.isEmpty }

    // MARK: Wording

    private static func counted(_ count: Int, _ singular: String, _ plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }

    private var spacePhrase: String {
        let spaces = Self.counted(spaceCount, "space", "spaces")
        return newSpaceCount > 0 ? "\(spaces) (\(newSpaceCount) new)" : spaces
    }

    /// Preview headline: "Add 46 items in 9 spaces (4 new)".
    var summary: String {
        guard hasAnythingToImport else { return "Nothing to add" }
        return "Add \(Self.counted(items.count, "item", "items")) in \(spacePhrase)"
    }

    /// Result alert: "Imported 46 items into 9 spaces (4 new). 5 duplicates skipped."
    var resultMessage: String {
        var message = "Imported \(Self.counted(items.count, "item", "items")) into \(spacePhrase)."
        if duplicateCount > 0 {
            message += " \(Self.counted(duplicateCount, "duplicate", "duplicates")) skipped."
        }
        return message
    }

    /// The warnings that apply, in the order the preview lists them. The
    /// free-plan line is separate (`freeLimitMessage`) because it carries the
    /// upgrade button.
    var warnings: [String] {
        var lines: [String] = []
        let noName = skipCount(.noName)
        if noName > 0 {
            lines.append(noName == 1
                ? "1 row has no item name and will be skipped"
                : "\(noName) rows have no item name and will be skipped")
        }
        let existing = skipCount(.alreadyExists)
        if existing > 0 {
            lines.append(existing == 1
                ? "1 item already exists and will be skipped"
                : "\(existing) items already exist and will be skipped")
        }
        let repeated = skipCount(.repeatedInFile)
        if repeated > 0 {
            lines.append(repeated == 1
                ? "1 row is an exact copy of an earlier row and will be skipped"
                : "\(repeated) rows are exact copies of earlier rows and will be skipped")
        }
        if unreadableQuantityCount > 0 {
            lines.append(unreadableQuantityCount == 1
                ? "1 quantity couldn't be read; the text is kept in notes"
                : "\(unreadableQuantityCount) quantities couldn't be read; the text is kept in notes")
        }
        if unreadableExpiryCount > 0 {
            lines.append(unreadableExpiryCount == 1
                ? "1 expiry date couldn't be read; the text is kept in notes"
                : "\(unreadableExpiryCount) expiry dates couldn't be read; the text is kept in notes")
        }
        if ignoredMinimumCount > 0 {
            lines.append(ignoredMinimumCount == 1
                ? "1 minimum was ignored because the row has no quantity"
                : "\(ignoredMinimumCount) minimums were ignored because the row has no quantity")
        }
        if let dateOrder, dateOrder.isMixed {
            lines.append("This file mixes day/month and month/day dates. Check the expiry dates after importing")
        }
        return lines
    }

    /// "Free plan: 18 of 25 items left. 18 will be imported and 28 skipped."
    /// Nil unless the free limit cuts the import short.
    func freeLimitMessage(remaining: Int, limit: Int) -> String? {
        let cut = skipCount(.freeLimit)
        guard cut > 0 else { return nil }
        return "Free plan: \(remaining) of \(limit) items left. \(items.count) will be imported and \(cut) skipped."
    }
}

// MARK: - Planner

nonisolated enum ImportPlanner {

    /// Paths deeper than this are cut short. Real trees are a handful of
    /// levels; `Location.maxAncestorDepth` treats 50 as corrupt.
    static let maxPathDepth = 20

    /// A location in the working tree: an existing one, or one this import
    /// might create.
    private nonisolated struct WorkingNode {
        var name: String
        var parent: Int?
        var existingID: UUID?
        var isUnsortedArea = false
        var childIndexByKey: [String: Int] = [:]
        var existingItemKeys: Set<String> = []
        /// Whole rows already planned into this location, for spotting
        /// exact copies.
        var fileRowKeys: Set<String> = []
        /// An item is being added here or somewhere beneath.
        var isUsed = false
        var receivesItems = false
    }

    static func plan(
        rows: [[String]],
        mapping: ImportMapping,
        options: ImportOptions = ImportOptions(),
        existing: ImportTreeSnapshot = ImportTreeSnapshot()
    ) -> ImportPlan {
        var plan = ImportPlan()
        let width = mapping.roles.count
        let headerRow = mapping.hasHeaderRow ? rows.first : nil
        let dataRows: [(number: Int, cells: [String])] = rows.enumerated().compactMap { index, cells in
            if mapping.hasHeaderRow, index == 0 { return nil }
            // Tolerate a mapping narrower or wider than the row.
            let padded = cells.count >= width ? cells : cells + Array(repeating: "", count: width - cells.count)
            return (index + 1, padded)
        }
        guard let nameColumn = mapping.column(for: .itemName) else { return plan }

        // MARK: Working tree

        // Index 0 is a virtual root standing above the top-level Areas.
        var nodes: [WorkingNode] = [WorkingNode(name: "", parent: nil)]
        var indexByID: [UUID: Int] = [:]
        // Oldest first, so when siblings share a name the oldest is matched.
        let sorted = existing.nodes.sorted {
            ($0.dateCreated, $0.id.uuidString) < ($1.dateCreated, $1.id.uuidString)
        }
        for node in sorted where indexByID[node.id] == nil {
            indexByID[node.id] = nodes.count
            var working = WorkingNode(name: node.name, parent: nil, existingID: node.id)
            working.existingItemKeys = Set(node.itemNames.map(ImportFieldParsing.matchKey))
            nodes.append(working)
        }
        for node in sorted {
            guard let index = indexByID[node.id] else { continue }
            // A parent missing from the snapshot leaves the node unreachable
            // rather than promoting it to a top-level Area.
            let parent: Int
            if let parentID = node.parentID {
                guard let parentIndex = indexByID[parentID], parentIndex != index else { continue }
                parent = parentIndex
            } else {
                parent = 0
            }
            nodes[index].parent = parent
            let key = ImportFieldParsing.matchKey(node.name)
            if nodes[parent].childIndexByKey[key] == nil { nodes[parent].childIndexByKey[key] = index }
        }

        // Walks up to the top level. Bounded and cycle-safe: a corrupted
        // parent loop in the snapshot yields a truncated path, not a hang.
        func path(of index: Int) -> [String] {
            var names: [String] = []
            var seen: Set<Int> = []
            var current: Int? = index
            while let node = current, node != 0, seen.insert(node).inserted, names.count < 60 {
                names.insert(nodes[node].name, at: 0)
                current = nodes[node].parent
            }
            return names
        }

        func child(of parent: Int, named name: String, isUnsortedArea: Bool = false) -> Int {
            let key = ImportFieldParsing.matchKey(name)
            if let found = nodes[parent].childIndexByKey[key] { return found }
            let index = nodes.count
            nodes.append(WorkingNode(name: name, parent: parent, isUnsortedArea: isUnsortedArea))
            nodes[parent].childIndexByKey[key] = index
            return index
        }

        let destinationIndex: Int
        if case .location(let id) = options.destination, let index = indexByID[id] {
            destinationIndex = index
        } else {
            destinationIndex = 0
        }

        // MARK: Column-wide decisions

        let pathColumn = mapping.column(for: .locationPath)
        let levelColumns = mapping.levelColumns
        let pathStyle = pathColumn.map { column in
            ImportFieldParsing.pathStyle(for: dataRows.map { $0.cells[column] })
        } ?? .slashes

        let expiryColumn = mapping.column(for: .expiry)
        if let expiryColumn {
            plan.dateOrder = ImportFieldParsing.resolveDateOrder(
                values: dataRows.map { $0.cells[expiryColumn] },
                regionDefault: options.regionDateOrder,
                chosen: options.dateOrder
            )
        }
        let dateOrder = plan.dateOrder?.order ?? options.regionDateOrder

        let quantityColumn = mapping.column(for: .quantity)
        let unitColumn = mapping.column(for: .unit)
        let minimumColumn = mapping.column(for: .minimum)
        let notesColumn = mapping.column(for: .notes)
        let linkColumns = mapping.columns(for: .link)
        let extraColumns = mapping.columns(for: .addToNotes)
        let columnLabels = (0..<width).map { index in
            ImportAutoMapper.columnLabel(heading: headerRow.flatMap { index < $0.count ? $0[index] : nil }, index: index)
        }

        // MARK: Rows

        var carriedPath: [String] = []
        var carriedLevels = Array(repeating: "", count: levelColumns.count)
        var remainingCapacity = options.remainingFreeCapacity.map { max(0, $0) }

        for (rowNumber, cells) in dataRows {

            // Where this row lives. Worked out before the name check, so a
            // heading row with a location and no item still sets the location
            // for the rows beneath it.
            var components: [String] = []
            if let pathColumn {
                let parts = ImportFieldParsing.splitPath(cells[pathColumn], style: pathStyle)
                if parts.isEmpty {
                    if !carriedPath.isEmpty { plan.fillDownApplies = true }
                    if options.fillDown { components = carriedPath }
                } else {
                    components = parts
                    carriedPath = parts
                }
            } else if !levelColumns.isEmpty {
                let values = levelColumns.map { ImportFieldParsing.singleLine(cells[$0]) }
                // Fill down per level: blank levels above the first value keep
                // the row above's, and a value at level N resets everything
                // below it (a new Cupboard means the old Shelf no longer applies).
                if let firstFilled = values.firstIndex(where: { !$0.isEmpty }) {
                    var resolved = values
                    for level in 0..<firstFilled where !carriedLevels[level].isEmpty {
                        plan.fillDownApplies = true
                        if options.fillDown { resolved[level] = carriedLevels[level] }
                    }
                    for level in firstFilled..<values.count { carriedLevels[level] = values[level] }
                    components = resolved.filter { !$0.isEmpty }
                } else {
                    if carriedLevels.contains(where: { !$0.isEmpty }) { plan.fillDownApplies = true }
                    if options.fillDown { components = carriedLevels.filter { !$0.isEmpty } }
                }
            }
            if components.count > maxPathDepth { components = Array(components.prefix(maxPathDepth)) }

            let name = ImportFieldParsing.singleLine(cells[nameColumn])
            guard !name.isEmpty else {
                plan.skipped.append(ImportPlan.SkippedRow(row: rowNumber, name: "", reason: .noName))
                continue
            }

            // Find (or pencil in) the target. Nothing pencilled in here is
            // created unless an item actually ends up in or under it.
            var target = destinationIndex
            if components.isEmpty {
                if destinationIndex == 0 {
                    target = child(of: 0, named: options.unsortedAreaName, isUnsortedArea: true)
                }
            } else {
                for component in components { target = child(of: target, named: component) }
            }

            let nameKey = ImportFieldParsing.matchKey(name)
            if options.skipDuplicates {
                if nodes[target].existingItemKeys.contains(nameKey) {
                    plan.skipped.append(ImportPlan.SkippedRow(row: rowNumber, name: name, reason: .alreadyExists))
                    continue
                }
                // Within the file, only an exact copy of an earlier row is a
                // duplicate. A shared name alone is not: a paint list can
                // hold two "Titanium White" from different brands.
                let rowKey = cells.map(ImportFieldParsing.matchKey).joined(separator: "\u{1F}")
                guard nodes[target].fileRowKeys.insert(rowKey).inserted else {
                    plan.skipped.append(ImportPlan.SkippedRow(row: rowNumber, name: name, reason: .repeatedInFile))
                    continue
                }
            }

            if let capacity = remainingCapacity {
                guard capacity > 0 else {
                    plan.skipped.append(ImportPlan.SkippedRow(row: rowNumber, name: name, reason: .freeLimit))
                    continue
                }
                remainingCapacity = capacity - 1
            }

            // MARK: Fields

            var fallbacks: [String] = []

            var quantity: Int?
            var unit: String?
            if let quantityColumn {
                switch ImportFieldParsing.parseQuantity(cells[quantityColumn]) {
                case .blank:
                    break
                case .value(let value, let trailingText):
                    quantity = value
                    // Text after the number is only the unit when there is no
                    // Unit column to say otherwise.
                    if unitColumn == nil, let trailingText { unit = ImportFieldParsing.parseUnit(trailingText) }
                case .unreadable(let text):
                    fallbacks.append("Quantity: \(text)")
                    plan.unreadableQuantityCount += 1
                }
            }
            // A unit only means something next to a quantity.
            if let unitColumn, quantity != nil { unit = ImportFieldParsing.parseUnit(cells[unitColumn]) }

            var minimum: Int?
            if let minimumColumn {
                switch ImportFieldParsing.parseQuantity(cells[minimumColumn]) {
                case .blank:
                    break
                case .value(let value, _):
                    if quantity == nil {
                        plan.ignoredMinimumCount += 1
                    } else if value > 0 {
                        minimum = value
                    }
                case .unreadable:
                    plan.ignoredMinimumCount += 1
                }
            }

            var expiry: ImportDay?
            if let expiryColumn {
                let text = ImportFieldParsing.singleLine(cells[expiryColumn])
                if !text.isEmpty {
                    expiry = ImportFieldParsing.parseDate(text, order: dateOrder)
                    if expiry == nil {
                        fallbacks.append("Expiry: \(text)")
                        plan.unreadableExpiryCount += 1
                    }
                }
            }

            let notes = ImportFieldParsing.assembleNotes(
                notes: notesColumn.map { cells[$0] },
                extras: extraColumns.map { (heading: columnLabels[$0], value: cells[$0]) },
                links: linkColumns.map { cells[$0] },
                fallbacks: fallbacks
            )

            // Mark the target and everything above it as needed.
            nodes[target].receivesItems = true
            var current: Int? = target
            while let index = current, index != 0, !nodes[index].isUsed {
                nodes[index].isUsed = true
                current = nodes[index].parent
            }

            plan.items.append(ImportPlan.PlannedItem(
                row: rowNumber,
                name: name,
                // Filled in below once the new locations are numbered.
                target: .new(target),
                path: path(of: target),
                quantity: quantity,
                unit: unit,
                minimum: minimum,
                expiry: expiry,
                notes: notes
            ))
        }

        // MARK: Locations to create

        // Working nodes were appended parent-before-child, so walking them in
        // order gives a parent-first list.
        var refByIndex: [Int: ImportPlan.LocationRef] = [:]
        for index in nodes.indices.dropFirst() {
            if let id = nodes[index].existingID {
                refByIndex[index] = .existing(id)
            } else if nodes[index].isUsed {
                refByIndex[index] = .new(plan.newLocations.count)
                let parent = nodes[index].parent ?? 0
                plan.newLocations.append(ImportPlan.NewLocation(
                    name: nodes[index].name,
                    parent: parent == 0 ? nil : refByIndex[parent],
                    path: path(of: index),
                    isUnsortedArea: nodes[index].isUnsortedArea
                ))
            }
        }
        for itemIndex in plan.items.indices {
            if case .new(let workingIndex) = plan.items[itemIndex].target, let ref = refByIndex[workingIndex] {
                plan.items[itemIndex].target = ref
            }
        }

        // Spaces on the imported paths: everything used below the destination,
        // plus the destination itself if items land directly in it.
        let destinationAncestry: Set<Int> = {
            var chain: Set<Int> = []
            var current: Int? = destinationIndex
            while let index = current, index != 0, chain.insert(index).inserted {
                current = nodes[index].parent
            }
            return chain
        }()
        for index in nodes.indices.dropFirst() where nodes[index].isUsed {
            if nodes[index].receivesItems { plan.targetSpaceCount += 1 }
            if !destinationAncestry.contains(index) || (index == destinationIndex && nodes[index].receivesItems) {
                plan.spaceCount += 1
            }
        }

        return plan
    }
}
