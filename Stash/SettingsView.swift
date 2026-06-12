//
//  SettingsView.swift
//  Stash
//
//  Phase 8: Settings screen. Stale threshold, JSON export, about, notifications placeholder.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

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

                // MARK: About

                Section("About") {
                    LabeledContent("App", value: "Stash")
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Build", value: buildNumber)
                }

            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
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
                    importJSON(from: url)
                case .failure:
                    importResultTitle = "Import Failed"
                    importResultMessage = "Could not open the file."
                    showImportResult = true
                }
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

    // MARK: - Import

    private func importJSON(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            importResultTitle = "Import Failed"
            importResultMessage = "Permission denied — could not access the file."
            showImportResult = true
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let data = try? Data(contentsOf: url) else {
            importResultTitle = "Import Failed"
            importResultMessage = "Could not read the file."
            showImportResult = true
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let root = try? decoder.decode(ImportRoot.self, from: data) else {
            importResultTitle = "Import Failed"
            importResultMessage = "The file is not a valid Stash export."
            showImportResult = true
            return
        }

        var itemCount = 0
        for area in root.areas {
            let location = Location(name: area.name, icon: area.icon, color: area.color, parent: nil)
            modelContext.insert(location)
            insertChildren(of: area, into: location, itemCount: &itemCount)
        }

        try? modelContext.save()

        let areaCount = root.areas.count
        let areaWord = areaCount == 1 ? "area" : "areas"
        let itemWord = itemCount == 1 ? "item" : "items"
        importResultTitle = "Import Complete"
        importResultMessage = "Imported \(areaCount) \(areaWord) and \(itemCount) \(itemWord)."
        showImportResult = true
    }

    private func insertChildren(of imported: ImportLocation, into location: Location, itemCount: inout Int) {
        for importedChild in imported.children ?? [] {
            let child = Location(name: importedChild.name, icon: importedChild.icon, color: importedChild.color, parent: location)
            modelContext.insert(child)
            insertChildren(of: importedChild, into: child, itemCount: &itemCount)
        }
        for importedItem in imported.items ?? [] {
            let item = Item(name: importedItem.name, location: location)
            item.notes = importedItem.notes
            item.quantity = importedItem.quantity
            item.unit = importedItem.unit
            item.minimumQuantity = importedItem.minimumQuantity
            item.expiryDate = importedItem.expiryDate
            if importedItem.orderStatus == OrderStatus.onOrder.rawValue {
                item.orderStatusRaw = OrderStatus.onOrder.rawValue
            }
            if let dateAdded = importedItem.dateAdded { item.dateAdded = dateAdded }
            if let lastVerified = importedItem.lastVerified { item.lastVerified = lastVerified }
            modelContext.insert(item)
            itemCount += 1
        }
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
    let children: [ExportLocation]
    let items: [ExportItem]

    init(from location: Location) {
        id = location.id.uuidString
        name = location.name
        icon = location.icon
        color = location.color
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
    let children: [ImportLocation]?
    let items: [ImportItem]?
}

private struct ImportItem: Decodable {
    let name: String
    let notes: String?
    let quantity: Int?
    let unit: String?
    let minimumQuantity: Int?
    let expiryDate: Date?
    let orderStatus: String?
    let dateAdded: Date?
    let lastVerified: Date?
}
