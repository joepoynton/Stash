//
//  SettingsView.swift
//  Stash
//
//  Phase 8: Settings screen. Stale threshold, JSON export, about, notifications placeholder.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import CloudKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(StoreKitManager.self) private var storeKit
    @Query(sort: \Location.dateCreated) private var allLocations: [Location]
    @Query private var allItems: [Item]

    @AppStorage("staleThresholdDays") private var staleThresholdDays = 90

    @State private var showExportConfirm = false
    @State private var exportURL: URL? = nil
    @State private var showShareSheet = false
    @State private var showImportPicker = false
    @State private var showImportResult = false
    @State private var importResultMessage = ""
    @State private var importResultTitle = "Import Complete"
    @State private var showUpgradePrompt = false
    @State private var upgradeMessage = ""
    @State private var isRestoring = false

    // Import confirmation (D6) — decoded and counted before any write.
    @State private var pendingImport: ImportRoot? = nil
    @State private var pendingAreaCount = 0
    @State private var pendingItemCount = 0
    @State private var showImportConfirm = false

    // iCloud account status (D7 / F10)
    @State private var iCloudStatusText = "Checking…"

    var body: some View {
        NavigationStack {
            Form {

                // MARK: Inventory

                Section {
                    Stepper(
                        "Stale after \(staleThresholdDays) days",
                        value: $staleThresholdDays,
                        in: 30...365,
                        step: 5
                    )
                } header: {
                    Text("Inventory")
                } footer: {
                    Text("Items not verified within this period appear in Needs Attention.")
                }

                // MARK: Data

                Section("Data") {
                    // Export — Pro only
                    if storeKit.isPro {
                        Button("Export Data") {
                            showExportConfirm = true
                        }
                    } else {
                        Button {
                            upgradeMessage = "Unlock Stash Pro to export your inventory as JSON."
                            showUpgradePrompt = true
                        } label: {
                            HStack {
                                Text("Export Data")
                                    .foregroundStyle(Color(.tertiaryLabel))
                                Spacer()
                                Text("Pro")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(.teal)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    // Import
                    Button("Import Data") {
                        if !storeKit.isPro && allItems.count >= FeatureFlags.freeItemLimit {
                            upgradeMessage = "You've used \(allItems.count) of \(FeatureFlags.freeItemLimit) free items. Unlock Stash Pro for unlimited items, photos, and data export."
                            showUpgradePrompt = true
                        } else {
                            showImportPicker = true
                        }
                    }
                    // Restore Purchases
                    Button {
                        Task {
                            isRestoring = true
                            await storeKit.restorePurchases()
                            isRestoring = false
                        }
                    } label: {
                        HStack {
                            Text("Restore Purchases")
                            if isRestoring {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isRestoring)
                }

                // MARK: Sync

                Section {
                    LabeledContent("iCloud", value: iCloudStatusText)
                } header: {
                    Text("Sync")
                } footer: {
                    Text("Your inventory backs up and syncs across your devices through iCloud.")
                }

                // MARK: Notifications

                Section("Notifications") {
                    HStack {
                        Text("Notifications")
                        Spacer()
                        Text("Coming Soon")
                            .foregroundStyle(Color(.tertiaryLabel))
                            .font(.subheadline)
                    }
                }

                // MARK: Tips (F11)

                Section("Tips") {
                    tipRow(icon: "hand.tap.fill", text: "Touch and hold any item for quick actions.")
                    tipRow(icon: "arrow.up.right.square", text: "Swipe an item to mark it out of place.")
                    tipRow(icon: "mappin.and.ellipse", text: "Tap an item's location path to jump straight there.")
                }

                // MARK: About

                Section("About") {
                    LabeledContent("App", value: "Stash")
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Build", value: buildNumber)
                }

            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .task { await refreshICloudStatus() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            // Confirmation before export — surfaces the photos-excluded note
            .confirmationDialog(
                "Export Inventory",
                isPresented: $showExportConfirm,
                titleVisibility: .visible
            ) {
                Button("Export as JSON") { exportAndShare() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Photos are not included in this export.")
            }
            // Share sheet
            .sheet(isPresented: $showShareSheet, onDismiss: cleanupExportFile) {
                if let url = exportURL {
                    ExportShareSheet(url: url)
                }
            }
            // File picker for JSON import
            .fileImporter(
                isPresented: $showImportPicker,
                allowedContentTypes: [UTType.json]
            ) { result in
                switch result {
                case .success(let url):
                    prepareImport(from: url)
                case .failure:
                    importResultTitle = "Import Failed"
                    importResultMessage = "Could not open the file."
                    showImportResult = true
                }
            }
            // Import confirmation — show what will be added before any write
            .alert("Import Data?", isPresented: $showImportConfirm) {
                Button("Import") { commitImport() }
                Button("Cancel", role: .cancel) { pendingImport = nil }
            } message: {
                Text("This will add \(pendingAreaCount) \(pendingAreaCount == 1 ? "area" : "areas") and \(pendingItemCount) \(pendingItemCount == 1 ? "item" : "items") alongside your existing data.")
            }
            // Import result feedback
            .alert(importResultTitle, isPresented: $showImportResult) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importResultMessage)
            }
            // Upgrade prompt
            .sheet(isPresented: $showUpgradePrompt) {
                UpgradePromptSheet(message: upgradeMessage)
            }
        }
    }

    // MARK: - About

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    // MARK: - Export

    private var rootLocations: [Location] {
        allLocations.filter { $0.parent == nil }
    }

    private func exportAndShare() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let export = ExportRoot(
            appVersion: appVersion,
            exportDate: Date(),
            areas: rootLocations.map { ExportLocation(from: $0) }
        )

        guard let data = try? encoder.encode(export) else { return }

        // Date prefix keeps filenames unique and human-readable
        let datePart = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let filename = "stash-export-\(datePart).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        guard (try? data.write(to: url)) != nil else { return }
        exportURL = url
        showShareSheet = true
    }

    private func cleanupExportFile() {
        guard let url = exportURL else { return }
        try? FileManager.default.removeItem(at: url)
        exportURL = nil
    }

    // MARK: - iCloud status (D7 / F10)

    private func refreshICloudStatus() async {
        do {
            let status = try await CKContainer.default().accountStatus()
            switch status {
            case .available:               iCloudStatusText = "Active"
            case .noAccount:               iCloudStatusText = "Not signed in"
            case .restricted:              iCloudStatusText = "Restricted"
            case .couldNotDetermine:       iCloudStatusText = "Unavailable"
            case .temporarilyUnavailable:  iCloudStatusText = "Temporarily unavailable"
            @unknown default:              iCloudStatusText = "Unknown"
            }
        } catch {
            iCloudStatusText = "Unavailable"
        }
    }

    // MARK: - Tips (F11)

    @ViewBuilder
    private func tipRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.teal)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color(.label))
        }
    }

    // MARK: - Import

    /// Reads + decodes the file (the only step that needs file access), counts
    /// what's inside, then asks for confirmation before writing anything (D6).
    private func prepareImport(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            showImportFailure("Permission denied — could not access the file.")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let data = try? Data(contentsOf: url) else {
            showImportFailure("Could not read the file.")
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let root = try? decoder.decode(ImportRoot.self, from: data) else {
            showImportFailure("The file is not a valid Stash export.")
            return
        }

        pendingImport = root
        pendingAreaCount = root.areas.count
        pendingItemCount = root.areas.reduce(0) { $0 + $1.itemCount }
        showImportConfirm = true
    }

    /// Performs the insert from the decoded, in-memory import. Enforces the
    /// free-tier item cap so an import can never push a free user over the
    /// limit (D6); locations themselves are not capped.
    private func commitImport() {
        guard let root = pendingImport else { return }
        pendingImport = nil

        var remaining = storeKit.isPro ? Int.max : max(0, FeatureFlags.freeItemLimit - allItems.count)
        var importedCount = 0
        var skipped = 0

        for area in root.areas {
            let location = Location(name: area.name, icon: area.icon, color: area.color, parent: nil)
            location.sortOrder = area.sortOrder ?? 0
            modelContext.insert(location)
            insertChildren(of: area, into: location, remaining: &remaining, importedCount: &importedCount, skipped: &skipped)
        }

        try? modelContext.save()

        let areaWord = pendingAreaCount == 1 ? "area" : "areas"
        let itemWord = importedCount == 1 ? "item" : "items"
        importResultTitle = "Import Complete"
        if skipped > 0 {
            let skippedWord = skipped == 1 ? "item was" : "items were"
            importResultMessage = "Imported \(pendingAreaCount) \(areaWord) and \(importedCount) \(itemWord). \(skipped) \(skippedWord) skipped because the free plan is limited to \(FeatureFlags.freeItemLimit) items — upgrade to Stash Pro for unlimited items."
        } else {
            importResultMessage = "Imported \(pendingAreaCount) \(areaWord) and \(importedCount) \(itemWord)."
        }
        showImportResult = true
    }

    private func insertChildren(of node: ImportLocation, into location: Location, remaining: inout Int, importedCount: inout Int, skipped: inout Int) {
        for importedChild in node.children ?? [] {
            let child = Location(name: importedChild.name, icon: importedChild.icon, color: importedChild.color, parent: location)
            child.sortOrder = importedChild.sortOrder ?? 0
            modelContext.insert(child)
            insertChildren(of: importedChild, into: child, remaining: &remaining, importedCount: &importedCount, skipped: &skipped)
        }
        for importedItem in node.items ?? [] {
            guard remaining > 0 else {
                skipped += 1
                continue
            }
            let item = Item(name: importedItem.name, location: location)
            item.notes = importedItem.notes
            item.quantity = importedItem.quantity
            item.unit = importedItem.unit
            item.minimumQuantity = importedItem.minimumQuantity
            item.expiryDate = importedItem.expiryDate
            if importedItem.orderStatus == OrderStatus.onOrder.rawValue {
                item.orderStatusRaw = OrderStatus.onOrder.rawValue
            }
            // D6: round-trip the previously-omitted state.
            item.isOutOfPlace = importedItem.isOutOfPlace ?? false
            item.outOfPlaceNote = importedItem.outOfPlaceNote
            // New items default to 'always verified'; honour an explicit value
            // from a Stash export, otherwise default to true.
            item.neverStale = importedItem.neverStale ?? true
            item.manuallyRestocking = importedItem.manuallyRestocking ?? false
            if let dateAdded = importedItem.dateAdded { item.dateAdded = dateAdded }
            if let lastVerified = importedItem.lastVerified { item.lastVerified = lastVerified }
            modelContext.insert(item)
            importedCount += 1
            remaining -= 1
        }
    }

    private func showImportFailure(_ message: String) {
        importResultTitle = "Import Failed"
        importResultMessage = message
        showImportResult = true
    }
}

// MARK: - Share sheet wrapper

private struct ExportShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Export data structures

private struct ExportRoot: Encodable {
    let appVersion: String
    let exportDate: Date
    let areas: [ExportLocation]
}

private struct ExportLocation: Encodable {
    let id: String
    let name: String
    let icon: String?
    let color: String?
    let sortOrder: Int
    let children: [ExportLocation]
    let items: [ExportItem]

    init(from location: Location) {
        id = location.id.uuidString
        name = location.name
        icon = location.icon
        color = location.color
        sortOrder = location.sortOrder
        children = location.childList
            .sorted { $0.name < $1.name }
            .map { ExportLocation(from: $0) }
        items = location.itemList
            .sorted { $0.name < $1.name }
            .map { ExportItem(from: $0) }
    }
}

private struct ExportItem: Encodable {
    let id: String
    let name: String
    let notes: String?
    let quantity: Int?
    let unit: String?
    let minimumQuantity: Int?
    let expiryDate: Date?
    let orderStatus: String
    let isOutOfPlace: Bool
    let outOfPlaceNote: String?
    let neverStale: Bool
    let manuallyRestocking: Bool
    let dateAdded: Date
    let lastVerified: Date

    init(from item: Item) {
        id = item.id.uuidString
        name = item.name
        notes = item.notes
        quantity = item.quantity
        unit = item.unit
        minimumQuantity = item.minimumQuantity
        expiryDate = item.expiryDate
        // Export the effective status (including derived .low) so the
        // JSON faithfully reflects the item's visible state.
        orderStatus = item.orderStatus.rawValue
        // D6: previously omitted, so a backup/restore round-trip lost this state.
        isOutOfPlace = item.isOutOfPlace
        outOfPlaceNote = item.outOfPlaceNote
        neverStale = item.neverStale
        manuallyRestocking = item.manuallyRestocking
        dateAdded = item.dateAdded
        lastVerified = item.lastVerified
    }
}

// MARK: - Import data structures

private struct ImportRoot: Decodable {
    let appVersion: String?
    let exportDate: Date?
    let areas: [ImportLocation]
}

private struct ImportLocation: Decodable {
    let name: String
    let icon: String?
    let color: String?
    let sortOrder: Int?            // Optional — older exports omit it.
    let children: [ImportLocation]?
    let items: [ImportItem]?

    /// Total items in this subtree, used for the pre-import confirmation count.
    var itemCount: Int {
        (items?.count ?? 0) + (children?.reduce(0) { $0 + $1.itemCount } ?? 0)
    }
}

private struct ImportItem: Decodable {
    let name: String
    let notes: String?
    let quantity: Int?
    let unit: String?
    let minimumQuantity: Int?
    let expiryDate: Date?
    let orderStatus: String?
    // Optional — older exports omit these (D6, backward-compatible).
    let isOutOfPlace: Bool?
    let outOfPlaceNote: String?
    let neverStale: Bool?
    let manuallyRestocking: Bool?
    let dateAdded: Date?
    let lastVerified: Date?
}
