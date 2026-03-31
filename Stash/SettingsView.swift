//
//  SettingsView.swift
//  Stash
//
//  Phase 8: Settings screen. Stale threshold, JSON export, about, notifications placeholder.
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Location.dateCreated) private var allLocations: [Location]

    @AppStorage("staleThresholdDays") private var staleThresholdDays = 90

    @State private var showExportConfirm = false
    @State private var exportURL: URL? = nil
    @State private var showShareSheet = false

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
                    Button("Export Data") {
                        showExportConfirm = true
                    }
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
