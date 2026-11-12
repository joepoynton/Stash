//
//  ImportMapping.swift
//  Stash
//
//  1.3 spreadsheet import (spec B4). The roles a spreadsheet column can play,
//  the headings that suggest each one, and the automatic first guess shown on
//  the "Match your columns" screen.
//
//  Foundation only and `nonisolated` throughout.
//

import Foundation

// MARK: - Roles

nonisolated enum ImportRole: Hashable, Sendable {
    case ignore
    case itemName
    /// One column holding a whole path, e.g. `Studio > Paint cabinet > Drawer 2`.
    case locationPath
    /// One of several columns, level 1 outermost (Room, Cupboard, Shelf).
    case locationLevel(Int)
    case quantity
    case unit
    case minimum
    case expiry
    case notes
    /// A URL, added to notes on its own line so it becomes tappable.
    case link
    /// Added to notes as `Heading: value`.
    case addToNotes

    static let maxLevels = 5

    /// Every role, in the order the column menu lists them.
    static let menuOrder: [ImportRole] =
        [.ignore, .itemName, .locationPath]
        + (1...maxLevels).map { .locationLevel($0) }
        + [.quantity, .unit, .minimum, .expiry, .notes, .link, .addToNotes]

    var title: String {
        switch self {
        case .ignore: return "Ignore"
        case .itemName: return "Item name"
        case .locationPath: return "Location (full path)"
        case .locationLevel(let level): return "Location level \(level)"
        case .quantity: return "Quantity"
        case .unit: return "Unit"
        case .minimum: return "Minimum"
        case .expiry: return "Expiry date"
        case .notes: return "Notes"
        case .link: return "Link"
        case .addToNotes: return "Add to notes"
        }
    }

    /// Roles that any number of columns can share.
    var allowsSeveralColumns: Bool {
        self == .ignore || self == .addToNotes
    }

    var isLocationLevel: Bool {
        if case .locationLevel = self { return true }
        return false
    }
}

// MARK: - Column description

/// What the mapping screen shows for one column.
nonisolated struct ImportColumn: Sendable, Equatable, Identifiable {
    var index: Int
    /// The heading cell, or "Column A" style when there is no heading.
    var label: String
    /// The first two non-empty values, as a hint to what the column holds.
    var samples: [String]

    var id: Int { index }
}

// MARK: - Mapping

nonisolated struct ImportMapping: Sendable, Equatable {
    var hasHeaderRow: Bool
    /// One role per column, left to right.
    private(set) var roles: [ImportRole]

    init(hasHeaderRow: Bool, roles: [ImportRole]) {
        self.hasHeaderRow = hasHeaderRow
        self.roles = roles
    }

    func column(for role: ImportRole) -> Int? {
        roles.firstIndex(of: role)
    }

    func columns(for role: ImportRole) -> [Int] {
        roles.indices.filter { roles[$0] == role }
    }

    /// Level columns, outermost first.
    var levelColumns: [Int] {
        roles.indices
            .compactMap { index -> (level: Int, column: Int)? in
                if case .locationLevel(let level) = roles[index] { return (level, index) }
                return nil
            }
            .sorted { $0.level < $1.level }
            .map(\.column)
    }

    var hasLocation: Bool {
        column(for: .locationPath) != nil || !levelColumns.isEmpty
    }

    /// Continue is only enabled once a column is the item name.
    var isReady: Bool {
        column(for: .itemName) != nil
    }

    /// Assigns a role, keeping the mapping consistent: a single-use role is
    /// taken off whichever column had it, and "full path" and "level N" are
    /// mutually exclusive (choosing one clears the other kind).
    mutating func setRole(_ role: ImportRole, forColumn column: Int) {
        guard roles.indices.contains(column) else { return }
        for index in roles.indices where index != column {
            let other = roles[index]
            if !role.allowsSeveralColumns, other == role { roles[index] = .ignore }
            if role == .locationPath, other.isLocationLevel { roles[index] = .ignore }
            if role.isLocationLevel, other == .locationPath { roles[index] = .ignore }
        }
        roles[column] = role
    }
}

// MARK: - Auto-mapping

nonisolated enum ImportAutoMapper {

    // Heading synonyms (spec B4). All lower case, punctuation already removed.
    private static let nameHeadings: Set<String> = ["name", "item", "item name", "thing", "what", "product", "title"]
    /// Also a notes heading: only the name when nothing above matched.
    private static let nameFallbackHeadings: Set<String> = ["description"]
    /// Last resort for the name (a paint list's "Colour" column).
    private static let nameLastResortHeadings: Set<String> = ["colour", "color"]
    private static let pathHeadings: Set<String> = ["location", "path", "where", "stored", "storage location", "kept"]
    private static let levelHeadings: Set<String> = [
        "area", "room", "space", "zone", "building", "cupboard", "cabinet", "wardrobe",
        "shelf", "drawer", "box", "bin", "container", "crate", "bag", "tub",
    ]
    private static let quantityHeadings: Set<String> = [
        "qty", "quantity", "count", "amount", "number", "no", "stock", "how many", "on hand",
    ]
    private static let unitHeadings: Set<String> = ["unit", "units", "uom", "size unit"]
    private static let minimumHeadings: Set<String> = [
        "min", "minimum", "min qty", "reorder", "reorder level", "reorder point", "par", "par level",
    ]
    private static let expiryHeadings: Set<String> = [
        "expiry", "expires", "expiry date", "exp", "best before", "bbe", "use by", "sell by",
    ]
    private static let notesHeadings: Set<String> = ["notes", "note", "comments", "comment", "details", "info", "description"]
    private static let linkHeadings: Set<String> = ["link", "url", "web", "website", "spreadsheet", "sheet"]

    private static let allHeadings: Set<String> =
        nameHeadings.union(nameFallbackHeadings).union(nameLastResortHeadings)
            .union(pathHeadings).union(levelHeadings).union(quantityHeadings).union(unitHeadings)
            .union(minimumHeadings).union(expiryHeadings).union(notesHeadings).union(linkHeadings)

    // MARK: Headings

    /// Lower case, punctuation turned into spaces, whitespace collapsed:
    /// "Use-by" → "use by", "Qty." → "qty".
    static func normaliseHeading(_ heading: String) -> String {
        let mapped = heading.lowercased().map { character -> Character in
            character.isLetter || character.isNumber ? character : " "
        }
        return ImportFieldParsing.singleLine(String(mapped))
    }

    /// True if the heading is in the set, or is a simple plural of something
    /// in it ("Items", "Locations").
    private static func matches(_ heading: String, _ set: Set<String>) -> Bool {
        if set.contains(heading) { return true }
        return heading.hasSuffix("s") && set.contains(String(heading.dropLast()))
    }

    /// "Column A", "Column B", … "Column AA".
    static func columnLetters(_ index: Int) -> String {
        var number = index + 1
        var letters = ""
        while number > 0 {
            let remainder = (number - 1) % 26
            letters = String(UnicodeScalar(UInt8(65 + remainder))) + letters
            number = (number - 1) / 26
        }
        return letters
    }

    /// The heading if there is one, otherwise "Column A" style.
    static func columnLabel(heading: String?, index: Int) -> String {
        let heading = ImportFieldParsing.singleLine(heading ?? "")
        return heading.isEmpty ? "Column \(columnLetters(index))" : heading
    }

    // MARK: Header detection

    private static func isNumeric(_ cell: String) -> Bool {
        !cell.isEmpty && Double(cell.replacingOccurrences(of: ",", with: "")) != nil
    }

    /// The "First row is headings" default (spec B4): on if a first-row cell
    /// is a known heading, or if the first row is all text above columns of
    /// numbers.
    static func detectHeaderRow(_ rows: [[String]]) -> Bool {
        guard rows.count >= 2, let first = rows.first else { return false }
        // Headings are words. A number in the first row means it is data.
        if first.contains(where: isNumeric) { return false }

        let headings = first.map(normaliseHeading)
        if first.count == 1 {
            // A one-column file is a plain list of names, and "Box" or "Bag"
            // is far more likely to be the first item than a heading. Only a
            // heading that means "item name" counts.
            return matches(headings[0], nameHeadings.union(nameFallbackHeadings))
        }
        if headings.contains(where: { matches($0, allHeadings) }) { return true }

        // Text in row 1 above a column that is numbers all the way down.
        let body = rows.dropFirst().prefix(20)
        for column in first.indices where !first[column].isEmpty {
            let cells = body.map { $0[column] }.filter { !$0.isEmpty }
            if !cells.isEmpty, cells.allSatisfy(isNumeric) { return true }
        }
        return false
    }

    // MARK: Columns

    static func columns(for rows: [[String]], hasHeaderRow: Bool) -> [ImportColumn] {
        guard let first = rows.first else { return [] }
        let body = hasHeaderRow ? rows.dropFirst() : rows[...]
        return first.indices.map { index in
            var samples: [String] = []
            for row in body where samples.count < 2 {
                let cell = ImportFieldParsing.singleLine(row[index])
                if !cell.isEmpty { samples.append(cell) }
            }
            return ImportColumn(
                index: index,
                label: columnLabel(heading: hasHeaderRow ? first[index] : nil, index: index),
                samples: samples
            )
        }
    }

    // MARK: Empty columns

    /// Removes columns with nothing in any row. Copying cells from Numbers or
    /// exporting a CSV often brings a run of empty columns along, which would
    /// only clutter the "Match your columns" screen.
    static func dropEmptyColumns(_ rows: [[String]]) -> [[String]] {
        guard let width = rows.map(\.count).max(), width > 0 else { return rows }
        let keep = (0..<width).filter { column in
            rows.contains { column < $0.count && !$0[column].isEmpty }
        }
        guard keep.count < width, !keep.isEmpty else { return rows }
        return rows.map { row in keep.map { $0 < row.count ? row[$0] : "" } }
    }

    // MARK: Auto-mapping

    /// The first guess at each column's role, from its heading. Each role is
    /// used once (first match from the left wins) except location levels.
    static func autoMap(rows: [[String]], hasHeaderRow: Bool? = nil) -> ImportMapping {
        let hasHeaderRow = hasHeaderRow ?? detectHeaderRow(rows)
        let columnCount = rows.first?.count ?? 0
        var roles = Array(repeating: ImportRole.ignore, count: columnCount)

        if hasHeaderRow, let first = rows.first {
            let headings = first.map(normaliseHeading)

            func claim(_ role: ImportRole, _ set: Set<String>) {
                guard !roles.contains(role) else { return }
                if let index = headings.indices.first(where: { roles[$0] == .ignore && matches(headings[$0], set) }) {
                    roles[index] = role
                }
            }

            claim(.itemName, nameHeadings)
            claim(.itemName, nameFallbackHeadings)

            // Locations. Two or more level headings become levels 1, 2, 3… in
            // column order; a single one becomes level 1. If the sheet has a
            // "Location"-style column as well ("Room" + "Location"), it joins
            // the levels in column order rather than competing with them.
            let pathColumns = headings.indices.filter { roles[$0] == .ignore && matches(headings[$0], pathHeadings) }
            let levelColumns = headings.indices.filter { roles[$0] == .ignore && matches(headings[$0], levelHeadings) }
            if levelColumns.isEmpty {
                if let path = pathColumns.first { roles[path] = .locationPath }
            } else {
                let ordered = (levelColumns + pathColumns).sorted().prefix(ImportRole.maxLevels)
                for (offset, column) in ordered.enumerated() { roles[column] = .locationLevel(offset + 1) }
            }

            claim(.quantity, quantityHeadings)
            claim(.unit, unitHeadings)
            claim(.minimum, minimumHeadings)
            claim(.expiry, expiryHeadings)
            claim(.notes, notesHeadings)
            claim(.link, linkHeadings)
            claim(.itemName, nameLastResortHeadings)
        }

        // A single column with no recognised heading is the item name.
        if columnCount == 1, !roles.contains(.itemName) { roles[0] = .itemName }

        return ImportMapping(hasHeaderRow: hasHeaderRow, roles: roles)
    }
}
