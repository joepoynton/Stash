//
//  AddItemSheet.swift
//  Stash
//

import SwiftUI
import SwiftData

struct AddItemSheet: View {
    let location: Location

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(StoreKitManager.self) private var storeKit
    @Query private var allItems: [Item]

    @State private var showUpgradePrompt = false
    @State private var name = ""
    @State private var notes = ""
    @State private var trackQuantity = false
    @State private var quantity = 0
    @State private var unit = ""
    @State private var minimumQuantity = 0
    @State private var hasExpiryDate = false
    @State private var expiryDate = Date()

    @FocusState private var nameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .focused($nameFocused)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    Toggle("Track Quantity", isOn: $trackQuantity.animation())
                    if trackQuantity {
                        // Current quantity — shared tap-to-type +/- control
                        NumericEntryField(
                            value: $quantity,
                            range: 0...9_999,
                            unit: unit.isEmpty ? nil : unit
                        )
                        .padding(.vertical, 4)

                        // Unit
                        HStack {
                            Text("Unit")
                            Spacer()
                            TextField("e.g. rolls, tablets", text: $unit)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 160)
                        }

                        // Minimum quantity — compact +/- after the label
                        HStack {
                            Text("Minimum")
                                .foregroundStyle(Color(.label))
                            Spacer()
                            NumericEntryField(
                                value: $minimumQuantity,
                                range: 0...9_999,
                                prominent: false
                            )
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    Toggle("Expiry Date", isOn: $hasExpiryDate.animation())
                    if hasExpiryDate {
                        DatePicker("Date", selection: $expiryDate, displayedComponents: .date)
                    }
                }

                // Bulk entry: save this item and keep the form open for the next one
                Section {
                    Button {
                        saveAndAddAnother()
                    } label: {
                        Label("Save & Add Another", systemImage: "plus.circle")
                            .foregroundStyle(.teal)
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("New Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { nameFocused = true }
            .sheet(isPresented: $showUpgradePrompt) {
                UpgradePromptSheet(
                    message: "You've used \(allItems.count) of \(FeatureFlags.freeItemLimit) free items. Unlock Stash Pro for unlimited items, photos, and data export."
                )
            }
        }
    }

    // MARK: - Save

    private func save() {
        guard commitItem() else { return }
        dismiss()
    }

    private func saveAndAddAnother() {
        guard commitItem() else { return }
        resetForm()
    }

    /// Builds and inserts the item. Returns false when nothing was saved
    /// (empty name, or free-tier cap hit — the cap is normally caught before
    /// this sheet opens; this is the backstop).
    private func commitItem() -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        guard storeKit.isPro || allItems.count < FeatureFlags.freeItemLimit else {
            showUpgradePrompt = true
            return false
        }

        // Insert first, then set the location so SwiftData maintains the
        // inverse `location.items` array in memory immediately (see QuickAdd).
        let item = Item(name: trimmed)
        modelContext.insert(item)
        item.location = location
        item.neverStale = true   // New items are 'always verified' by default (opt-in staleness).
        item.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil
                     : notes.trimmingCharacters(in: .whitespacesAndNewlines)

        if trackQuantity {
            item.quantity = quantity
            let trimmedUnit = unit.trimmingCharacters(in: .whitespaces)
            item.unit = trimmedUnit.isEmpty ? nil : String(trimmedUnit.prefix(20))
            item.minimumQuantity = minimumQuantity > 0 ? minimumQuantity : nil
        }

        item.expiryDate = hasExpiryDate ? expiryDate : nil
        UserDefaults.standard.set(location.id.uuidString, forKey: "lastUsedLocationID")
        return true
    }

    private func resetForm() {
        name = ""
        notes = ""
        trackQuantity = false
        quantity = 0
        unit = ""
        minimumQuantity = 0
        hasExpiryDate = false
        expiryDate = Date()
        nameFocused = true
    }
}
