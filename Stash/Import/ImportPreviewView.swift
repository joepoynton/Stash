//
//  ImportPreviewView.swift
//  Stash
//
//  1.3 spreadsheet import (spec B7). Shows what the import would do, built from
//  the plan; nothing is written until Import is tapped.
//

import SwiftUI
import SwiftData

// MARK: - Wording shared by the preview screens

extension ImportPlan.PlannedItem {
    /// "Garage › Shelf 2 › AA batteries"
    var displayLine: String {
        (path + [name]).joined(separator: " › ")
    }

    /// "×12 boxes", or nil when there is no quantity.
    var quantityText: String? {
        guard let quantity else { return nil }
        if let unit, !unit.isEmpty { return "×\(quantity) \(unit)" }
        return "×\(quantity)"
    }
}

extension ImportPlan.SkipReason {
    var label: String {
        switch self {
        case .noName: return "No item name"
        case .alreadyExists: return "Already in Stash"
        case .repeatedInFile: return "Repeats an earlier row"
        case .freeLimit: return "Over the free plan limit"
        }
    }
}

// MARK: - Preview

struct ImportPreviewView: View {
    var model: SpreadsheetImportModel
    var showAllRows: () -> Void
    var onFinished: (String) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(StoreKitManager.self) private var storeKit

    @State private var showDestinationPicker = false
    @State private var pickerExpandedIDs: Set<UUID> = []
    @State private var showUpgradePrompt = false
    @State private var isWriting = false
    @State private var failureMessage: String?

    private static let sampleCount = 20
    private static let newSpaceListLimit = 8

    var body: some View {
        Group {
            if let plan = model.plan {
                content(plan)
            } else {
                ProgressView("Checking your spreadsheet…")
            }
        }
        .navigationTitle("Preview")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model.plan == nil { model.preparePreview(in: modelContext, isPro: storeKit.isPro) }
        }
        .sheet(isPresented: $showDestinationPicker) {
            LocationPickerSheet(
                title: "Import Into",
                excludedIDs: [],
                allowTopLevel: true,
                expandedIDs: $pickerExpandedIDs,
                onSelect: { location in model.setDestination(location) }
            )
        }
        .sheet(isPresented: $showUpgradePrompt) {
            UpgradePromptSheet(message: "Unlock Stash Pro to import your whole spreadsheet, with unlimited items, photos and data export.")
        }
        .alert("Nothing Was Imported", isPresented: failureBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(failureMessage ?? "")
        }
    }

    private var failureBinding: Binding<Bool> {
        Binding(get: { failureMessage != nil }, set: { if !$0 { failureMessage = nil } })
    }

    // MARK: Content

    private func content(_ plan: ImportPlan) -> some View {
        List {
            summarySection(plan)
            optionsSection(plan)
            freePlanSection(plan)
            warningsSection(plan)
            sampleSection(plan)
        }
        .opacity(model.isPlanning ? 0.6 : 1)
        .safeAreaInset(edge: .bottom) { importBar(plan) }
    }

    // MARK: Summary

    private func summarySection(_ plan: ImportPlan) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(plan.summary)
                    .font(.title3.bold())
                if plan.hasAnythingToImport, plan.newSpaceCount > 0 {
                    Text("New spaces are created for the places Stash doesn't already have.")
                        .font(.footnote)
                        .foregroundStyle(Color(.secondaryLabel))
                }
            }
            .padding(.vertical, 2)

            ForEach(Array(plan.newLocations.prefix(Self.newSpaceListLimit).enumerated()), id: \.offset) { _, location in
                Label(location.path.joined(separator: " › "), systemImage: "plus.circle")
                    .font(.subheadline)
                    .foregroundStyle(.teal)
            }
            if plan.newLocations.count > Self.newSpaceListLimit {
                Text("and \(plan.newLocations.count - Self.newSpaceListLimit) more new spaces")
                    .font(.footnote)
                    .foregroundStyle(Color(.secondaryLabel))
            }
        }
    }

    // MARK: Options

    private func optionsSection(_ plan: ImportPlan) -> some View {
        Section {
            Button {
                showDestinationPicker = true
            } label: {
                HStack {
                    Text("Import into")
                        .foregroundStyle(Color(.label))
                    Spacer()
                    Text(model.destinationPath ?? "Top level")
                        .foregroundStyle(Color(.secondaryLabel))
                        .lineLimit(1)
                        .truncationMode(.head)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color(.tertiaryLabel))
                }
            }

            if plan.fillDownApplies {
                Toggle("Blank location means same as the row above", isOn: Binding(
                    get: { model.options.fillDown },
                    set: { model.setFillDown($0) }
                ))
            }

            Toggle("Skip duplicates", isOn: Binding(
                get: { model.options.skipDuplicates },
                set: { model.setSkipDuplicates($0) }
            ))

            if let decision = plan.dateOrder {
                dateOrderRow(decision)
            }
        } header: {
            Text("Options")
        } footer: {
            if model.options.skipDuplicates {
                Text("An item is skipped if Stash already has one with that name in the same space, or if the row is an exact copy of an earlier row.")
            }
        }
    }

    @ViewBuilder
    private func dateOrderRow(_ decision: ImportDateOrderDecision) -> some View {
        if decision.ambiguousCount > 0 || decision.source == .chosen {
            VStack(alignment: .leading, spacing: 8) {
                Text(decision.order.summary)
                Picker("Date order", selection: Binding(
                    get: { decision.order },
                    set: { model.setDateOrder($0) }
                )) {
                    Text("Day / month").tag(ImportDateOrder.dayFirst)
                    Text("Month / day").tag(ImportDateOrder.monthFirst)
                }
                .pickerStyle(.segmented)
            }
            .padding(.vertical, 2)
        } else {
            // Something in the column settles it, so there is nothing to choose.
            Text(decision.order.summary)
                .foregroundStyle(Color(.secondaryLabel))
        }
    }

    // MARK: Free plan

    @ViewBuilder
    private func freePlanSection(_ plan: ImportPlan) -> some View {
        if let remaining = model.remainingFreeCapacity,
           let message = plan.freeLimitMessage(remaining: remaining, limit: FeatureFlags.freeItemLimit) {
            Section {
                Label(message, systemImage: "lock.fill")
                    .font(.subheadline)
                Button("Unlock Stash Pro") { showUpgradePrompt = true }
            }
        }
    }

    // MARK: Warnings

    @ViewBuilder
    private func warningsSection(_ plan: ImportPlan) -> some View {
        let warnings = plan.warnings
        if !warnings.isEmpty {
            Section {
                ForEach(warnings, id: \.self) { warning in
                    Label {
                        Text(warning)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    .font(.subheadline)
                }
            } header: {
                Text("Worth knowing")
            }
        }
    }

    // MARK: Sample

    @ViewBuilder
    private func sampleSection(_ plan: ImportPlan) -> some View {
        if !plan.items.isEmpty {
            Section {
                ForEach(plan.items.prefix(Self.sampleCount), id: \.row) { item in
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.displayLine)
                            .font(.subheadline)
                            .lineLimit(2)
                        Spacer(minLength: 8)
                        if let quantity = item.quantityText {
                            Text(quantity)
                                .font(.subheadline)
                                .foregroundStyle(Color(.secondaryLabel))
                        }
                    }
                }
                if plan.items.count > Self.sampleCount {
                    Button("Show all \(plan.items.count) items") { showAllRows() }
                }
            } header: {
                Text("First \(min(Self.sampleCount, plan.items.count)) items")
            }
        } else if !plan.skipped.isEmpty {
            Section {
                Button("Show skipped rows") { showAllRows() }
            }
        }
    }

    // MARK: Import button

    private func importBar(_ plan: ImportPlan) -> some View {
        Button {
            performImport(plan)
        } label: {
            HStack {
                if isWriting { ProgressView().tint(.white) }
                Text(plan.hasAnythingToImport
                     ? "Import \(plan.items.count) \(plan.items.count == 1 ? "Item" : "Items")"
                     : "Nothing to Import")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(.teal)
        .disabled(!plan.hasAnythingToImport || model.isPlanning || isWriting)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func performImport(_ plan: ImportPlan) {
        isWriting = true
        do {
            try ImportWriter.apply(plan, in: modelContext)
            Haptics.write()
            isWriting = false
            onFinished(plan.resultMessage)
        } catch {
            isWriting = false
            failureMessage = error.localizedDescription
        }
    }
}

// MARK: - Every row

/// The full list of what would be added, and what would be skipped and why.
struct ImportAllRowsView: View {
    var model: SpreadsheetImportModel

    var body: some View {
        List {
            if let plan = model.plan {
                if !plan.items.isEmpty {
                    Section("To add (\(plan.items.count))") {
                        ForEach(plan.items, id: \.row) { item in
                            HStack(alignment: .firstTextBaseline) {
                                Text(item.displayLine)
                                    .font(.subheadline)
                                Spacer(minLength: 8)
                                if let quantity = item.quantityText {
                                    Text(quantity)
                                        .font(.subheadline)
                                        .foregroundStyle(Color(.secondaryLabel))
                                }
                            }
                        }
                    }
                }
                if !plan.skipped.isEmpty {
                    Section("Skipped (\(plan.skipped.count))") {
                        ForEach(plan.skipped, id: \.row) { skipped in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(skipped.name.isEmpty ? "Row \(skipped.row)" : skipped.name)
                                    .font(.subheadline)
                                Text(skipped.reason.label)
                                    .font(.caption)
                                    .foregroundStyle(Color(.secondaryLabel))
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("All Rows")
        .navigationBarTitleDisplayMode(.inline)
    }
}
