//
//  SpreadsheetParser.swift
//  Stash
//
//  1.3 spreadsheet import (spec B3). Turns a CSV/TSV file or a pasted block of
//  cells into rows of trimmed strings, working out the encoding and delimiter.
//
//  Foundation only and `nonisolated` throughout, so it can run off the main
//  actor and be exercised from scripts/import-check on the command line.
//

import Foundation

// MARK: - Result types

nonisolated enum SpreadsheetDelimiter: String, CaseIterable, Sendable {
    case comma, tab, semicolon, pipe
    /// No delimiter found: every line is one cell (a plain list of names).
    case none

    var character: Character? {
        switch self {
        case .comma: return ","
        case .tab: return "\t"
        case .semicolon: return ";"
        case .pipe: return "|"
        case .none: return nil
        }
    }
}

nonisolated struct ParsedSpreadsheet: Sendable, Equatable {
    /// Trimmed cells, fully blank rows dropped, short rows padded so every
    /// row has `columnCount` cells.
    var rows: [[String]]
    var delimiter: SpreadsheetDelimiter
    /// Human-readable name of the text encoding that decoded the file
    /// ("Pasted text" for the paste route). Diagnostic only.
    var encoding: String

    var columnCount: Int { rows.first?.count ?? 0 }
}

nonisolated enum SpreadsheetParseError: Error, Equatable, Sendable {
    case empty
    case tooLarge
    case tooManyRows
    /// A zipped document: .xlsx, .numbers and friends.
    case spreadsheetDocument
    case notText

    /// Plain-English message for the import flow.
    var message: String {
        switch self {
        case .empty:
            return "There's nothing in this file to import."
        case .tooLarge:
            return "This file is larger than 5 MB. Split it into smaller files and import them one at a time."
        case .tooManyRows:
            return "This file has more than 10,000 rows. Split it into smaller files and import them one at a time."
        case .spreadsheetDocument:
            return "This is an Excel or Numbers document, which Stash can't read directly. Export it as CSV first, or copy the rows and use Paste Rows."
        case .notText:
            return "This doesn't look like a text or CSV file."
        }
    }
}

// MARK: - Parser

nonisolated enum SpreadsheetParser {

    static let maxBytes = 5 * 1024 * 1024
    static let maxRows = 10_000
    /// How many records the delimiter detection looks at.
    private static let sampleRecords = 20

    // MARK: Entry points

    /// Parses the contents of a file.
    static func parse(data: Data, delimiter forced: SpreadsheetDelimiter? = nil) throws -> ParsedSpreadsheet {
        guard data.count <= maxBytes else { throw SpreadsheetParseError.tooLarge }
        let (text, encoding) = try decode(data)
        return try parse(text: text, encoding: encoding, forced: forced)
    }

    /// Parses pasted text (copying cells in Numbers, Excel or Google Sheets
    /// puts tab-separated text on the clipboard).
    static func parse(text: String, delimiter forced: SpreadsheetDelimiter? = nil) throws -> ParsedSpreadsheet {
        guard text.utf8.count <= maxBytes else { throw SpreadsheetParseError.tooLarge }
        return try parse(text: text, encoding: "Pasted text", forced: forced)
    }

    private static func parse(text: String, encoding: String, forced: SpreadsheetDelimiter?) throws -> ParsedSpreadsheet {
        var scalars = Array(text.unicodeScalars)
        if scalars.first == "\u{FEFF}" { scalars.removeFirst() }

        // Excel's optional "sep=;" first line names the delimiter outright.
        var hinted: SpreadsheetDelimiter?
        if let hint = separatorHint(in: scalars) {
            hinted = hint.delimiter
            scalars.removeFirst(hint.length)
        }

        let delimiter = forced ?? hinted ?? detectDelimiter(in: scalars)
        var records = try tokenize(scalars, delimiter: delimiter, limit: maxRows)

        // Trim every cell, drop fully blank rows, pad to the widest row.
        records = records
            .map { $0.map(trimCell) }
            .filter { row in row.contains { !$0.isEmpty } }
        guard !records.isEmpty else { throw SpreadsheetParseError.empty }
        let width = records.map(\.count).max() ?? 0
        records = records.map { row in
            row.count < width ? row + Array(repeating: "", count: width - row.count) : row
        }
        return ParsedSpreadsheet(rows: records, delimiter: delimiter, encoding: encoding)
    }

    // MARK: Encoding

    /// UTF-8, then UTF-16, then Windows-1252, then Mac Roman (spec B3).
    /// Windows-1252 accepts almost any bytes and Mac Roman accepts all of
    /// them, so binary files are rejected up front instead of being decoded
    /// into nonsense.
    static func decode(_ data: Data) throws -> (text: String, encoding: String) {
        guard !data.isEmpty else { throw SpreadsheetParseError.empty }
        let bytes = [UInt8](data)

        // .xlsx and .numbers are zip archives.
        if bytes.starts(with: [0x50, 0x4B, 0x03, 0x04]) { throw SpreadsheetParseError.spreadsheetDocument }

        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            if let text = String(validatingUTF8Bytes: bytes.dropFirst(3)) { return (text, "UTF-8 (with BOM)") }
        }
        if bytes.starts(with: [0xFF, 0xFE]) {
            return (decodeUTF16(bytes.dropFirst(2), littleEndian: true), "UTF-16 LE")
        }
        if bytes.starts(with: [0xFE, 0xFF]) {
            return (decodeUTF16(bytes.dropFirst(2), littleEndian: false), "UTF-16 BE")
        }

        let nulCount = bytes.reduce(0) { $0 + ($1 == 0 ? 1 : 0) }
        if nulCount == 0, let text = String(validatingUTF8Bytes: bytes[...]) {
            return (text, "UTF-8")
        }

        // UTF-16 without a BOM: ASCII text shows up as a NUL in every other byte.
        if nulCount > 0 {
            let evenNULs = stride(from: 0, to: bytes.count, by: 2).reduce(0) { $0 + (bytes[$1] == 0 ? 1 : 0) }
            let oddNULs = nulCount - evenNULs
            let pairs = bytes.count / 2
            if bytes.count % 2 == 0, pairs > 0 {
                if oddNULs * 10 >= pairs * 6, evenNULs * 10 <= pairs {
                    return (decodeUTF16(bytes[...], littleEndian: true), "UTF-16 LE")
                }
                if evenNULs * 10 >= pairs * 6, oddNULs * 10 <= pairs {
                    return (decodeUTF16(bytes[...], littleEndian: false), "UTF-16 BE")
                }
            }
            throw SpreadsheetParseError.notText
        }

        if let text = String(data: data, encoding: .windowsCP1252) { return (text, "Windows-1252") }
        if let text = String(data: data, encoding: .macOSRoman) { return (text, "Mac Roman") }
        if let text = String(data: data, encoding: .isoLatin1) { return (text, "Latin-1") }
        throw SpreadsheetParseError.notText
    }

    private static func decodeUTF16(_ bytes: ArraySlice<UInt8>, littleEndian: Bool) -> String {
        var units: [UInt16] = []
        units.reserveCapacity(bytes.count / 2)
        var index = bytes.startIndex
        while index + 1 < bytes.endIndex {
            let first = UInt16(bytes[index]), second = UInt16(bytes[index + 1])
            units.append(littleEndian ? (second << 8 | first) : (first << 8 | second))
            index += 2
        }
        return String(decoding: units, as: UTF16.self)
    }

    // MARK: Delimiter detection

    private static func separatorHint(in scalars: [Unicode.Scalar]) -> (delimiter: SpreadsheetDelimiter, length: Int)? {
        // The hint is exactly five characters ("sep=" plus the delimiter)
        // followed by a line ending.
        guard scalars.count > 5,
              String(String.UnicodeScalarView(scalars.prefix(4))).lowercased() == "sep=",
              scalars[5] == "\r" || scalars[5] == "\n",
              let delimiter = SpreadsheetDelimiter.allCases.first(where: {
                  $0.character?.unicodeScalars.first == scalars[4]
              })
        else { return nil }
        // Swallow the line ending too (\n, \r or \r\n).
        var length = 6
        if scalars[5] == "\r", scalars.count > 6, scalars[6] == "\n" { length = 7 }
        return (delimiter, length)
    }

    /// Scores comma, tab, semicolon and pipe over the first 20 records and
    /// picks the one giving the most consistent column count greater than 1.
    /// Works on records rather than raw lines so a quoted newline doesn't
    /// count as two short rows.
    static func detectDelimiter(in scalars: [Unicode.Scalar]) -> SpreadsheetDelimiter {
        // On a tie the delimiter least likely to appear in ordinary cell text
        // wins: tabs and pipes are rare in prose, commas are everywhere.
        let candidates: [SpreadsheetDelimiter] = [.tab, .pipe, .semicolon, .comma]
        var best: (delimiter: SpreadsheetDelimiter, consistency: Double)?

        for candidate in candidates {
            guard let sample = try? tokenize(scalars, delimiter: candidate, limit: sampleRecords, stopAtLimit: true) else { continue }
            let widths = sample
                .filter { row in row.contains { !trimCell($0).isEmpty } }
                .map(\.count)
            guard !widths.isEmpty else { continue }

            var tally: [Int: Int] = [:]
            for width in widths { tally[width, default: 0] += 1 }
            // The most common width; on a tie, the wider one.
            guard let mode = tally.max(by: { ($0.value, $0.key) < ($1.value, $1.key) }) else { continue }
            guard mode.key > 1 else { continue }

            let consistency = Double(mode.value) / Double(widths.count)
            // Under 60% of rows agreeing is cell text that happens to contain
            // the character, not a delimiter.
            guard consistency >= 0.6 else { continue }
            if best == nil || consistency > best!.consistency {
                best = (candidate, consistency)
            }
        }
        return best?.delimiter ?? .none
    }

    // MARK: Tokenizer

    /// Splits text into records and cells. Quoting follows RFC 4180 (quoted
    /// cells may hold delimiters, newlines and doubled quotes) with two bits
    /// of leniency for real-world files:
    /// - a quote only opens a quoted cell at the very start of the cell, so
    ///   `2" nails` is left alone;
    /// - if a quoted cell never closes, the text is re-read with quotes
    ///   treated as ordinary characters rather than swallowing the file.
    static func tokenize(
        _ scalars: [Unicode.Scalar],
        delimiter: SpreadsheetDelimiter,
        limit: Int,
        stopAtLimit: Bool = false
    ) throws -> [[String]] {
        if let records = try tokenize(scalars, delimiter: delimiter, limit: limit, stopAtLimit: stopAtLimit, honourQuotes: true) {
            return records
        }
        return try tokenize(scalars, delimiter: delimiter, limit: limit, stopAtLimit: stopAtLimit, honourQuotes: false) ?? []
    }

    /// Returns nil when a quoted cell is left open at the end of the text.
    private static func tokenize(
        _ scalars: [Unicode.Scalar],
        delimiter: SpreadsheetDelimiter,
        limit: Int,
        stopAtLimit: Bool,
        honourQuotes: Bool
    ) throws -> [[String]]? {
        let delimiterScalar = delimiter.character?.unicodeScalars.first
        var records: [[String]] = []
        var record: [String] = []
        var cell = String.UnicodeScalarView()
        var atCellStart = true
        var inQuotes = false
        var index = 0
        let count = scalars.count

        func endCell() {
            record.append(String(cell))
            cell = String.UnicodeScalarView()
            atCellStart = true
        }

        while index < count {
            let scalar = scalars[index]

            if inQuotes {
                if scalar == "\"" {
                    if index + 1 < count, scalars[index + 1] == "\"" {
                        cell.append("\"")
                        index += 2
                        continue
                    }
                    inQuotes = false
                } else if scalar == "\r" {
                    // Normalise line endings inside a quoted cell to \n.
                    cell.append("\n")
                    if index + 1 < count, scalars[index + 1] == "\n" { index += 1 }
                } else {
                    cell.append(scalar)
                }
                index += 1
                continue
            }

            if scalar == "\"", honourQuotes, atCellStart {
                inQuotes = true
                atCellStart = false
            } else if let delimiterScalar, scalar == delimiterScalar {
                endCell()
            } else if scalar == "\n" || scalar == "\r" {
                if scalar == "\r", index + 1 < count, scalars[index + 1] == "\n" { index += 1 }
                endCell()
                records.append(record)
                record = []
                if records.count > limit {
                    if stopAtLimit { return Array(records.prefix(limit)) }
                    throw SpreadsheetParseError.tooManyRows
                }
            } else {
                // Leading spaces don't stop a quote from opening the cell.
                if scalar != " " { atCellStart = false }
                cell.append(scalar)
            }
            index += 1
        }

        if inQuotes { return nil }
        if !cell.isEmpty || !record.isEmpty {
            endCell()
            records.append(record)
        }
        if records.count > limit {
            if stopAtLimit { return Array(records.prefix(limit)) }
            throw SpreadsheetParseError.tooManyRows
        }
        return records
    }

    private static func trimCell(_ cell: String) -> String {
        cell.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Strict UTF-8

private nonisolated extension String {
    /// Nil unless the bytes are valid UTF-8 (no lossy repair).
    init?(validatingUTF8Bytes bytes: ArraySlice<UInt8>) {
        self.init(data: Data(bytes), encoding: .utf8)
    }
}
