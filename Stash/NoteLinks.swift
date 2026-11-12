//
//  NoteLinks.swift
//  Stash
//
//  1.3 Part A: web links found in an item's notes, shown as tappable rows in
//  ItemDetailSheet. Lets an item point at a spreadsheet (or anything else)
//  that holds the detail, without a dedicated Link field.
//

import Foundation

/// One web link found in an item's notes. Plain value with no ties to the
/// main actor.
nonisolated struct NoteLink: Identifiable, Hashable, Sendable {
    let url: URL
    /// True when the URL looks like a spreadsheet (Numbers, Google Sheets,
    /// Excel on OneDrive/SharePoint, or a spreadsheet file).
    let isSpreadsheet: Bool
    /// The host with any leading "www." removed, e.g. "icloud.com".
    let host: String

    var id: URL { url }
    var title: String { isSpreadsheet ? "Open Spreadsheet" : "Open Link" }
    var systemImage: String { isSpreadsheet ? "tablecells" : "link" }

    init(url: URL) {
        self.url = url
        self.isSpreadsheet = Self.looksLikeSpreadsheet(url)
        self.host = Self.displayHost(url)
    }

    static func looksLikeSpreadsheet(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        let hostAndPath = (url.host() ?? "").lowercased() + path
        let markers = ["icloud.com/numbers", "docs.google.com/spreadsheets", "onedrive", "sharepoint", "1drv.ms"]
        if markers.contains(where: { hostAndPath.contains($0) }) { return true }
        return [".xlsx", ".xls", ".csv", ".numbers"].contains { path.hasSuffix($0) }
    }

    static func displayHost(_ url: URL) -> String {
        let host = (url.host() ?? "").lowercased()
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

enum NoteLinks {

    /// At most this many link rows are shown.
    static let maxLinks = 3

    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// The http/https links in `notes`, in order, without repeats, up to
    /// `maxLinks`. Other schemes (mailto, tel, file) are left out: local file
    /// paths don't survive sync between devices.
    static func links(in notes: String?) -> [NoteLink] {
        guard let notes, !notes.isEmpty, let detector = Self.detector else { return [] }
        var seen = Set<URL>()
        var links: [NoteLink] = []
        let range = NSRange(notes.startIndex..<notes.endIndex, in: notes)
        for match in detector.matches(in: notes, options: [], range: range) {
            guard let url = match.url,
                  let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
                  seen.insert(url).inserted else { continue }
            links.append(NoteLink(url: url))
            if links.count == maxLinks { break }
        }
        return links
    }
}
