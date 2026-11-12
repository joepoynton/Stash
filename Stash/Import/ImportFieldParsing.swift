//
//  ImportFieldParsing.swift
//  Stash
//
//  1.3 spreadsheet import (spec B5 path splitting, B6 field parsing). Turns the
//  text in a cell into a quantity, unit, date or location path.
//
//  Foundation only and `nonisolated` throughout. Nothing here uses
//  DateFormatter, Calendar.current or the device locale, so a given cell
//  parses the same way on an iPhone as it does in scripts/import-check.
//

import Foundation

// MARK: - Calendar day

/// A calendar day with no time or time zone. Dates stay in this form through
/// planning and only become a `Date` when the import is written, so the plan
/// doesn't depend on where or when it was computed.
nonisolated struct ImportDay: Hashable, Sendable, Comparable {
    var year: Int
    var month: Int
    var day: Int

    static func < (lhs: ImportDay, rhs: ImportDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// Midday on this day in the given calendar's time zone. Midday rather
    /// than midnight so the day doesn't slip when the item syncs to a device
    /// in a neighbouring time zone.
    func date(in calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
    }

    /// dd/MM/yyyy, for previews and diagnostics.
    var dayMonthYear: String {
        func pad(_ value: Int, _ width: Int) -> String {
            let text = String(value)
            return String(repeating: "0", count: max(0, width - text.count)) + text
        }
        return "\(pad(day, 2))/\(pad(month, 2))/\(pad(year, 4))"
    }

    static func daysInMonth(_ month: Int, year: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: return 31
        case 4, 6, 9, 11: return 30
        case 2: return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        default: return 0
        }
    }

    /// Nil unless the three parts make a real date in a sensible year.
    static func validated(year: Int, month: Int, day: Int) -> ImportDay? {
        guard (1900...2200).contains(year), (1...12).contains(month),
              day >= 1, day <= daysInMonth(month, year: year) else { return nil }
        return ImportDay(year: year, month: month, day: day)
    }

    static func lastDay(ofMonth month: Int, year: Int) -> ImportDay? {
        validated(year: year, month: month, day: daysInMonth(month, year: year))
    }
}

// MARK: - Date order

nonisolated enum ImportDateOrder: String, Sendable {
    case dayFirst, monthFirst

    var summary: String {
        switch self {
        case .dayFirst: return "Dates read as day/month/year"
        case .monthFirst: return "Dates read as month/day/year"
        }
    }
}

/// How the day-first / month-first question was settled for a date column.
nonisolated struct ImportDateOrderDecision: Sendable, Equatable {
    nonisolated enum Source: Sendable, Equatable {
        /// A value in the column can only be read one way (e.g. 31/03 or 12/31).
        case detected
        /// Nothing in the column settles it, so the device's region decides.
        case regionDefault
        /// Chosen by the user on the preview screen.
        case chosen
    }
    var order: ImportDateOrder
    var source: Source
    /// The column holds some values that can only be day-first and others
    /// that can only be month-first.
    var isMixed: Bool
    /// How many values could be read either way. Zero means the choice makes
    /// no difference to this file.
    var ambiguousCount: Int
}

// MARK: - Quantity

nonisolated enum ImportQuantity: Sendable, Equatable {
    /// Empty cell: quantity tracking stays off.
    case blank
    /// A whole number, plus any text that followed it ("3 tubes" → "tubes").
    case value(Int, trailingText: String?)
    /// Text that isn't a quantity ("about a dozen"). Kept in notes.
    case unreadable(String)
}

// MARK: - Field parsing

nonisolated enum ImportFieldParsing {

    static let maxUnitLength = 20
    /// The app's quantity controls stop at 9,999. Anything larger is almost
    /// certainly a mis-mapped column (a barcode, a year, a phone number).
    static let maxQuantity = 9_999

    // MARK: Text

    /// Collapses line breaks and runs of whitespace to single spaces. For
    /// names, units and location names, which must stay on one line.
    static func singleLine(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    /// The form two names are compared in: trimmed, whitespace collapsed,
    /// case ignored, and accents normalised to one representation.
    static func matchKey(_ text: String) -> String {
        singleLine(text).precomposedStringWithCanonicalMapping.lowercased()
    }

    // MARK: Quantity

    /// Accepts `3`, `3.0`, `x3`, `3x`, `×3`, `3 tubes`, `3 x 37ml`, `1,000`.
    /// Takes the leading whole number; decimals round down; negatives become 0.
    static func parseQuantity(_ raw: String) -> ImportQuantity {
        let text = singleLine(raw)
        guard !text.isEmpty else { return .blank }
        var rest = Substring(text)

        // Leading multiplier: "x3", "× 3".
        if let first = rest.first, isMultiplier(first),
           let next = rest.dropFirst().drop(while: { $0 == " " }).first, next.isASCIIDigit {
            rest = rest.dropFirst().drop(while: { $0 == " " })
        }

        var negative = false
        if let first = rest.first, first == "-" || first == "\u{2212}" || first == "+" {
            negative = first != "+"
            rest = rest.dropFirst()
        }

        let digits = rest.prefix(while: { $0.isASCIIDigit })
        guard !digits.isEmpty else { return .unreadable(text) }
        rest = rest.dropFirst(digits.count)
        var whole = String(digits)

        // Thousands groups: a comma followed by exactly three digits.
        if whole.count <= 3 {
            while rest.first == ",", rest.dropFirst().prefix(while: { $0.isASCIIDigit }).count == 3 {
                whole += rest.dropFirst().prefix(3)
                rest = rest.dropFirst(4)
            }
        }
        // Decimal part, dropped (quantities are whole numbers).
        if let mark = rest.first, mark == "." || mark == ",",
           let next = rest.dropFirst().first, next.isASCIIDigit {
            rest = rest.dropFirst().drop(while: { $0.isASCIIDigit })
        }

        guard let magnitude = Int(whole), magnitude <= maxQuantity else { return .unreadable(text) }
        let quantity = negative ? 0 : magnitude

        var trailing = rest.trimmingCharacters(in: .whitespaces)
        if trailing.allSatisfy({ $0 == "." || $0 == "," }) { trailing = "" }
        // A bare multiplier ("3x") says nothing about the unit.
        if trailing.count == 1, let only = trailing.first, isMultiplier(only) { trailing = "" }
        guard let first = trailing.first else { return .value(quantity, trailingText: nil) }
        // "3/4" or "2-3" isn't a count followed by a unit.
        guard first.isLetter || first == "×" || first == "(" else { return .unreadable(text) }
        return .value(quantity, trailingText: trailing)
    }

    private static func isMultiplier(_ character: Character) -> Bool {
        character == "x" || character == "X" || character == "×"
    }

    /// Single line, at most 20 characters (the app's existing unit rule).
    static func parseUnit(_ raw: String) -> String? {
        let text = String(singleLine(raw).prefix(maxUnitLength)).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    // MARK: Dates

    private nonisolated enum DateToken {
        case number(Int, digits: Int)
        case month(Int)
    }

    private static let monthNames: [String: Int] = {
        let full = ["january", "february", "march", "april", "may", "june", "july",
                    "august", "september", "october", "november", "december"]
        var table: [String: Int] = ["sept": 9]
        for (index, name) in full.enumerated() {
            table[name] = index + 1
            table[String(name.prefix(3))] = index + 1
        }
        return table
    }()

    /// Splits a date cell into number and month-name tokens. Nil if anything
    /// else is in there.
    private static func dateTokens(_ raw: String) -> [DateToken]? {
        var text = singleLine(raw).lowercased()
        guard !text.isEmpty else { return nil }

        // ISO date-times: keep the date, drop the time ("2027-03-31T00:00:00Z").
        if let tIndex = text.firstIndex(of: "t"), text[..<tIndex].allSatisfy({ $0.isASCIIDigit || $0 == "-" }),
           text[..<tIndex].contains("-"), text[text.index(after: tIndex)...].first?.isASCIIDigit == true {
            text = String(text[..<tIndex])
        }
        // A trailing clock time ("31/03/2027 00:00", "… 12:00:00 am").
        var words = text.split(separator: " ").map(String.init)
        while let last = words.last, words.count > 1, last.contains(":") || last == "am" || last == "pm" {
            words.removeLast()
        }
        text = words.joined(separator: " ")

        var tokens: [DateToken] = []
        for piece in text.split(whereSeparator: { " /-.,".contains($0) }) {
            var word = String(piece)
            if word.allSatisfy(\.isASCIIDigit) {
                guard word.count <= 5, let value = Int(word) else { return nil }
                tokens.append(.number(value, digits: word.count))
                continue
            }
            // Ordinals: 1st, 2nd, 3rd, 31st.
            for suffix in ["st", "nd", "rd", "th"] where word.hasSuffix(suffix) {
                let stem = word.dropLast(2)
                if !stem.isEmpty, stem.count <= 2, stem.allSatisfy(\.isASCIIDigit) { word = String(stem) }
            }
            if word.allSatisfy(\.isASCIIDigit), let value = Int(word) {
                tokens.append(.number(value, digits: word.count))
            } else if let month = monthNames[word] {
                tokens.append(.month(month))
            } else {
                return nil
            }
        }
        return tokens
    }

    /// Two-digit years are 2000s: expiry dates are not in the 1900s.
    private static func fullYear(_ value: Int, digits: Int) -> Int? {
        switch digits {
        case 4: return value
        case 2: return 2000 + value
        default: return nil
        }
    }

    /// Which way round a numeric date must be read, if it can only be read
    /// one way. `31/03/2027` is day-first evidence, `12/31/2027` month-first,
    /// `03/01/2027` is nil.
    static func dateOrderEvidence(_ raw: String) -> ImportDateOrder? {
        guard let tokens = dateTokens(raw), tokens.count == 3,
              case .number(let first, let firstDigits) = tokens[0],
              case .number(let second, _) = tokens[1],
              case .number = tokens[2],
              firstDigits <= 2 else { return nil }
        if first > 12, second <= 12 { return .dayFirst }
        if second > 12, first <= 12 { return .monthFirst }
        return nil
    }

    /// True for a numeric date that reads validly both ways round.
    static func isAmbiguousDate(_ raw: String) -> Bool {
        guard let tokens = dateTokens(raw), tokens.count == 3,
              case .number(let first, let firstDigits) = tokens[0],
              case .number(let second, _) = tokens[1],
              case .number = tokens[2],
              firstDigits <= 2 else { return false }
        return (1...12).contains(first) && (1...12).contains(second) && first != second
    }

    /// Decides day-first or month-first for a whole column (spec B6): any
    /// value with a first part over 12 makes it day-first, any with a second
    /// part over 12 makes it month-first, otherwise the region default.
    static func resolveDateOrder(
        values: [String],
        regionDefault: ImportDateOrder,
        chosen: ImportDateOrder? = nil
    ) -> ImportDateOrderDecision {
        var sawDayFirst = false, sawMonthFirst = false, ambiguous = 0
        for value in values {
            switch dateOrderEvidence(value) {
            case .dayFirst: sawDayFirst = true
            case .monthFirst: sawMonthFirst = true
            case nil: if isAmbiguousDate(value) { ambiguous += 1 }
            }
        }
        let isMixed = sawDayFirst && sawMonthFirst
        if let chosen {
            return ImportDateOrderDecision(order: chosen, source: .chosen, isMixed: isMixed, ambiguousCount: ambiguous)
        }
        if sawDayFirst != sawMonthFirst {
            return ImportDateOrderDecision(order: sawDayFirst ? .dayFirst : .monthFirst, source: .detected,
                                           isMixed: false, ambiguousCount: ambiguous)
        }
        return ImportDateOrderDecision(order: regionDefault, source: .regionDefault, isMixed: isMixed, ambiguousCount: ambiguous)
    }

    /// Reads a date cell. `order` only matters for numeric dates that could
    /// be read either way; a value that can only be read one way is read that
    /// way regardless. Month-and-year values become the last day of the month.
    static func parseDate(_ raw: String, order: ImportDateOrder) -> ImportDay? {
        guard let tokens = dateTokens(raw) else { return nil }

        switch tokens.count {
        case 1:
            // Excel serial number: days since 30/12/1899.
            guard case .number(let serial, let digits) = tokens[0], digits == 5,
                  (20_000...80_000).contains(serial),
                  singleLine(raw).allSatisfy({ $0.isASCIIDigit }) else { return nil }
            return day(fromExcelSerial: serial)

        case 2:
            switch (tokens[0], tokens[1]) {
            case (.number(let month, let digits), .number(let year, 4)) where digits <= 2:
                return ImportDay.lastDay(ofMonth: month, year: year)          // 11/2026
            case (.number(let year, 4), .number(let month, let digits)) where digits <= 2:
                return ImportDay.lastDay(ofMonth: month, year: year)          // 2026-11
            case (.month(let month), .number(let year, 4)):
                return ImportDay.lastDay(ofMonth: month, year: year)          // Nov 2026
            default:
                // An Excel serial with a time fraction ("46477.5").
                if case .number(let serial, 5) = tokens[0], case .number = tokens[1],
                   (20_000...80_000).contains(serial),
                   singleLine(raw).allSatisfy({ $0.isASCIIDigit || $0 == "." }) {
                    return day(fromExcelSerial: serial)
                }
                return nil
            }

        case 3:
            switch (tokens[0], tokens[1], tokens[2]) {
            case (.number(let year, 4), .number(let month, _), .number(let day, _)):
                return ImportDay.validated(year: year, month: month, day: day)   // 2027-03-31
            case (.number(let first, let firstDigits), .number(let second, let secondDigits), .number(let yearValue, let yearDigits))
                where firstDigits <= 2 && secondDigits <= 2:
                guard let year = fullYear(yearValue, digits: yearDigits) else { return nil }
                let dayFirst = ImportDay.validated(year: year, month: second, day: first)
                let monthFirst = ImportDay.validated(year: year, month: first, day: second)
                switch order {
                case .dayFirst: return dayFirst ?? monthFirst
                case .monthFirst: return monthFirst ?? dayFirst
                }
            case (.number(let day, let dayDigits), .month(let month), .number(let yearValue, let yearDigits))
                where dayDigits <= 2:                                            // 31 Mar 2027, 31-Mar-27
                guard let year = fullYear(yearValue, digits: yearDigits) else { return nil }
                return ImportDay.validated(year: year, month: month, day: day)
            case (.month(let month), .number(let day, let dayDigits), .number(let year, 4))
                where dayDigits <= 2:                                            // March 31, 2027
                return ImportDay.validated(year: year, month: month, day: day)
            default:
                return nil
            }

        default:
            return nil
        }
    }

    /// Excel's day count (1900 date system) to a calendar day.
    private static func day(fromExcelSerial serial: Int) -> ImportDay? {
        // 25,569 days separate Excel's day zero (30/12/1899) from 01/01/1970.
        // The rest is the standard days-to-civil-date conversion.
        let shifted = serial - 25_569 + 719_468
        let era = shifted / 146_097
        let dayOfEra = shifted - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthIndex = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthIndex + 2) / 5 + 1
        let month = monthIndex < 10 ? monthIndex + 3 : monthIndex - 9
        let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
        return ImportDay.validated(year: year, month: month, day: day)
    }

    // MARK: Location paths

    nonisolated enum PathStyle: Sendable, Equatable {
        /// The column uses `>` or `›` (or an arrow) somewhere: split on those only.
        case arrows
        /// Otherwise split on ` / ` (with spaces), `\` or `|`.
        case slashes
    }

    private static let arrowSeparators = ["->", "→", "»", "›", ">"]

    static func pathStyle(for values: [String]) -> PathStyle {
        values.contains { value in value.contains(">") || value.contains("›") || value.contains("→") || value.contains("»") }
            ? .arrows : .slashes
    }

    /// Splits a full-path cell into location names. Never splits on a bare
    /// `/`, which turns up in real names ("A4/A3 paper").
    static func splitPath(_ raw: String, style: PathStyle) -> [String] {
        let marker = "\u{1F}"
        var text = singleLine(raw)
        switch style {
        case .arrows:
            for separator in arrowSeparators { text = text.replacingOccurrences(of: separator, with: marker) }
        case .slashes:
            for separator in [" / ", "\\", "|"] { text = text.replacingOccurrences(of: separator, with: marker) }
        }
        return text
            .components(separatedBy: marker)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: Notes

    /// Notes column first, then each "Add to notes" column as `Heading: value`,
    /// then link URLs, then any `Quantity:` / `Expiry:` fallbacks. One per line.
    static func assembleNotes(
        notes: String?,
        extras: [(heading: String, value: String)],
        links: [String],
        fallbacks: [String]
    ) -> String? {
        var lines: [String] = []
        if let notes {
            let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { lines.append(trimmed) }
        }
        for extra in extras {
            let value = extra.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { lines.append("\(extra.heading): \(value)") }
        }
        for link in links {
            let value = link.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { lines.append(value) }
        }
        lines.append(contentsOf: fallbacks)
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}

// MARK: - Helpers

private nonisolated extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
