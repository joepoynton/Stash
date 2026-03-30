//
//  ItemDetailSheet.swift
//  Stash
//

import SwiftUI
import SwiftData

struct ItemDetailSheet: View {
    @Bindable var item: Item

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(RecentlyAccessedStore.self) private var recentStore

    @State private var showMoveSheet = false
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                // On-order banner
                if item.orderStatus == .onOrder {
                    Section {
                        Label("On its way", systemImage: "shippingbox.fill")
                            .foregroundStyle(.orange)
                            .fontWeight(.medium)
                    }
                }

                // Name
                Section {
                    TextField("Name", text: $item.name)
                        .font(.headline)
                }

                // Location + Move
                Section {
                    HStack {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(Color(.secondaryLabel))
                            .frame(width: 24)
                        Text(locationPath)
                            .foregroundStyle(Color(.label))
                    }
                    Button {
                        showMoveSheet = true
                    } label: {
                        Label("Move to…", systemImage: "arrow.up.arrow.down")
                            .foregroundStyle(.teal)
                    }
                }

                // Notes
                Section("Notes") {
                    TextField("Add notes…", text: notesBinding, axis: .vertical)
                        .lineLimit(3...8)
                }

                // Quantity
                if item.quantity != nil {
                    quantitySection
                }

                // Expiry
                Section {
                    Toggle("Track expiry date", isOn: Binding(
                        get: { item.expiryDate != nil },
                        set: { item.expiryDate = $0 ? (item.expiryDate ?? Date()) : nil }
                    ))

                    if item.expiryDate != nil {
                        DatePicker(
                            "Expiry date",
                            selection: Binding(
                                get: { item.expiryDate ?? Date() },
                                set: { item.expiryDate = $0 }
                            ),
                            displayedComponents: .date
                        )

                        let expiringSoon = (item.expiryDate ?? .distantFuture).timeIntervalSinceNow < 30 * 86400
                        if expiringSoon {
                            Label("Expires soon", systemImage: "exclamationmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                // Verification + dates
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Last verified")
                                .font(.caption)
                                .foregroundStyle(Color(.secondaryLabel))
                            Text(item.lastVerified.relativeDescription)
                                .font(.subheadline)
                        }
                        Spacer()
                        Button("Mark as Verified") {
                            item.markAsVerified()
                        }
                        .buttonStyle(.bordered)
                        .tint(.teal)
                    }
                    Text("Added \(item.dateAdded.formatted(date: .long, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(Color(.secondaryLabel))
                }

                // Delete
                Section {
                    Button("Delete Item", role: .destructive) {
                        showDeleteConfirm = true
                    }
                }
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                recentStore.record(itemID: item.id)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showMoveSheet) {
                LocationPickerSheet(
                    title: "Move to…",
                    excludedIDs: [],
                    allowTopLevel: false,
                    onSelect: { newLocation in
                        if let loc = newLocation {
                            item.location = loc
                            item.lastVerified = Date()
                        }
                    }
                )
            }
            .alert("Delete \"\(item.name)\"?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    modelContext.delete(item)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone.")
            }
        }
    }

    // MARK: - Quantity section

    private var quantitySection: some View {
        Section("Quantity") {
            HStack {
                Button {
                    item.decrementQuantity()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                        .foregroundStyle((item.quantity ?? 0) == 0 ? Color(.tertiaryLabel) : .teal)
                }
                .buttonStyle(.plain)
                .disabled((item.quantity ?? 0) == 0)

                Spacer()

                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("\(item.quantity ?? 0)")
                        .font(.title.monospacedDigit())
                    if let unit = item.unit, !unit.isEmpty {
                        Text(unit)
                            .font(.title3)
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                }

                Spacer()

                Button {
                    item.incrementQuantity()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.teal)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 4)

            if let min = item.minimumQuantity {
                Text("Minimum: \(min)\(item.unit.map { " \($0)" } ?? "")")
                    .font(.caption)
                    .foregroundStyle(Color(.secondaryLabel))
            }

            switch item.orderStatus {
            case .low:
                Label("Low stock", systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.teal)
            case .onOrder:
                Label("On order", systemImage: "shippingbox")
                    .font(.caption)
                    .foregroundStyle(.orange)
            case .normal:
                EmptyView()
            }
        }
    }

    // MARK: - Helpers

    private var locationPath: String {
        guard let location = item.location else { return "No location" }
        var parts: [String] = []
        var current: Location? = location
        while let loc = current {
            parts.insert(loc.name, at: 0)
            current = loc.parent
        }
        return parts.joined(separator: " › ")
    }

    private var notesBinding: Binding<String> {
        Binding(
            get: { item.notes ?? "" },
            set: { item.notes = $0.isEmpty ? nil : $0 }
        )
    }
}

// MARK: - Date helper

private extension Date {
    var relativeDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
