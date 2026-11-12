//
//  SpreadsheetImportModel.swift
//  Stash
//
//  1.3 spreadsheet import. The state shared by the three screens of the flow:
//  the parsed rows, the column mapping, the options, and the plan worked out
//  from them. Planning runs off the main actor (ImportPlanner is pure and
//  nonisolated); this class only holds the results.
//

import Foundation
import Observation
import SwiftData

@Observable
final class SpreadsheetImportModel {

    // MARK: Input

    private(set) var rows: [[String]] = []
    private(set) var columns: [ImportColumn] = []
    private(set) var mapping = ImportMapping(hasHeaderRow: false, roles: [])

    // MARK: Options (preview screen)

    private(set) var options = ImportOptions()
    /// Where "Import into" points, for display. Nil means the top level.
    private(set) var destinationPath: String?

    // MARK: Plan

    private(set) var plan: ImportPlan?
    private(set) var isPlanning = false
    /// How many more items a free user may add. Nil for Pro.
    private(set) var remainingFreeCapacity: Int?

    private var snapshot = ImportTreeSnapshot()
    private var generation = 0

    // MARK: Loading

    /// Starts a fresh import from parsed rows and makes the first guess at
    /// the column roles.
    func load(_ parsed: ParsedSpreadsheet) {
        rows = parsed.rows
        let mapping = ImportAutoMapper.autoMap(rows: parsed.rows)
        self.mapping = mapping
        columns = ImportAutoMapper.columns(for: parsed.rows, hasHeaderRow: mapping.hasHeaderRow)
        options = ImportOptions()
        options.regionDateOrder = Self.deviceDateOrder()
        destinationPath = nil
        plan = nil
    }

    // MARK: Columns screen

    /// Flipping the heading toggle re-runs the automatic mapping, because
    /// which row is the headings changes what every column is called.
    func setHasHeaderRow(_ value: Bool) {
        guard value != mapping.hasHeaderRow else { return }
        mapping = ImportAutoMapper.autoMap(rows: rows, hasHeaderRow: value)
        columns = ImportAutoMapper.columns(for: rows, hasHeaderRow: value)
        plan = nil
    }

    func setRole(_ role: ImportRole, forColumn column: Int) {
        mapping.setRole(role, forColumn: column)
        plan = nil
    }

    // MARK: Preview screen

    /// Called when the preview opens: copies the existing tree for the
    /// planner and works out how many items a free user has left.
    func preparePreview(in context: ModelContext, isPro: Bool) {
        let locations = (try? context.fetch(FetchDescriptor<Location>())) ?? []
        snapshot = ImportWriter.snapshot(of: locations)
        if isPro {
            remainingFreeCapacity = nil
        } else {
            let count = (try? context.fetchCount(FetchDescriptor<Item>())) ?? 0
            remainingFreeCapacity = max(0, FeatureFlags.freeItemLimit - count)
        }
        options.remainingFreeCapacity = remainingFreeCapacity
        replan()
    }

    func setDestination(_ location: Location?) {
        options.destination = location.map { .location($0.id) } ?? .topLevel
        destinationPath = location?.pathString
        replan()
    }

    func setFillDown(_ value: Bool) {
        options.fillDown = value
        replan()
    }

    func setSkipDuplicates(_ value: Bool) {
        options.skipDuplicates = value
        replan()
    }

    func setDateOrder(_ value: ImportDateOrder) {
        options.dateOrder = value
        replan()
    }

    /// Works the plan out again off the main actor. If another change comes
    /// in while it runs, the older result is dropped.
    private func replan() {
        generation += 1
        let current = generation
        isPlanning = true
        let rows = rows, mapping = mapping, options = options, snapshot = snapshot
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = ImportPlanner.plan(rows: rows, mapping: mapping, options: options, existing: snapshot)
            await self?.finishPlanning(result, generation: current)
        }
    }

    private func finishPlanning(_ result: ImportPlan, generation finished: Int) {
        guard finished == generation else { return }
        plan = result
        isPlanning = false
    }

    // MARK: Region

    /// Day-first or month-first for dates that could be read either way,
    /// from the device's region (so UK devices read 03/04/2027 as 3 April).
    private static func deviceDateOrder() -> ImportDateOrder {
        let format = DateFormatter.dateFormat(fromTemplate: "yMd", options: 0, locale: .current) ?? ""
        guard let day = format.firstIndex(of: "d"), let month = format.firstIndex(of: "M") else { return .dayFirst }
        return month < day ? .monthFirst : .dayFirst
    }
}
