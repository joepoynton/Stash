//
//  QuickAddSheet.swift
//  Stash
//
//  Rapid-fire item entry: type a name, hit return, repeat. Each saved item
//  appears in a list below with an "Add detail" escape hatch into the full
//  detail sheet.
//
//  Two modes:
//  - Fixed location (Browse "+"): items land in the given location, no picker.
//  - Pickable location (Home "New Item"): a location chip under the text field
//    defaults to the last place an item was added and opens the tree picker.
//

import SwiftUI
import SwiftData

struct QuickAddSheet: View {
    /// When non-nil, every item is added here and the location chip is hidden.
    let fixedLocation: Location?

    init(location: Location? = nil) {
        self.fixedLocation = location
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(StoreKitManager.self) private var storeKit
    @Query private var allItems: [Item]
    @Query private var allLocations: [Location]

    @AppStorage("lastUsedLocationID") private var lastUsedLocationID = ""

    @State private var name = ""
    @State private var addedItems: [Item] = []
    @State private var itemToDetail: Item? = nil
    @State private var showUpgradePrompt = false
    @State private var selectedLocation: Location? = nil
    @State private var showLocationPicker = false
    @State private var pickerExpandedIDs: Set<UUID> = []
    @FocusState private var focused: Bool

    /// Where the next saved item goes.
    private var targetLocation: Location? {
        fixedLocation ?? selectedLocation
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                TextField("Item name", text: $name)
                    .font(.body)
                    .padding()
                    .focused($focused)
                    .onSubmit { saveAndClear() }
                    .submitLabel(.return)

                // Location chip — pickable mode only
                if fixedLocation == nil {
                    Button {
                        focused = false
                        showLocationPicker = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "mappin.and.ellipse")
                            Text(selectedLocation?.pathString ?? "Choose a space…")
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .fontWeight(.semibold)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.teal)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                }

                Divider()

                if !addedItems.isEmpty {
                    List(addedItems) { item in
                        HStack {
                            Text(item.name)
                                .foregroundStyle(Color(.label))
                            Spacer()
                            Button("Add detail") {
                                // Unfocus the text field so the new sheet
                                // gets clean keyboard state.
                                focused = false
                                itemToDetail = item
                            }
                            .font(.subheadline)
                            .foregroundStyle(.teal)
                            .buttonStyle(.plain)
                        }
                    }
                    .listStyle(.plain)
                } else {
                    Spacer()
                }
            }
            .navigationTitle("Quick Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                focused = true
                if fixedLocation == nil && selectedLocation == nil {
                    selectedLocation = lastUsedLocation
                }
            }
            .sheet(item: $itemToDetail, onDismiss: { focused = true }) {
                ItemDetailSheet(item: $0)
            }
            .sheet(isPresented: $showLocationPicker, onDismiss: { focused = true }) {
                LocationPickerSheet(
                    title: "Add to…",
                    excludedIDs: [],
                    allowTopLevel: false,
                    expandedIDs: $pickerExpandedIDs,
                    onSelect: { location in
                        if let location { selectedLocation = location }
                    }
                )
            }
            .sheet(isPresented: $showUpgradePrompt, onDismiss: { focused = true }) {
                UpgradePromptSheet(
                    message: "You've used \(allItems.count) of \(FeatureFlags.freeItemLimit) free items. Unlock Stash Pro for unlimited items, photos, and data export."
                )
            }
        }
    }

    /// The location where an item was most recently added, if it still exists.
    private var lastUsedLocation: Location? {
        guard let uuid = UUID(uuidString: lastUsedLocationID) else { return nil }
        return allLocations.first { $0.id == uuid }
    }

    private func saveAndClear() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        guard let location = targetLocation else {
            focused = false
            showLocationPicker = true
            return
        }
        guard storeKit.isPro || allItems.count < FeatureFlags.freeItemLimit else {
            focused = false
            showUpgradePrompt = true
            return
        }
        let item = Item(name: trimmed, location: location)
        modelContext.insert(item)
        lastUsedLocationID = location.id.uuidString
        addedItems.insert(item, at: 0)   // newest at top
        name = ""
        focused = true
    }
}
