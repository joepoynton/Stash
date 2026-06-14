//
//  SearchResultsView.swift
//  Stash
//
//  Reusable live-search results, shared by the Home and Browse tabs.
//  Searches item names, notes, and location names. Items and Spaces stay
//  in separate sections. Matching is diacritic- and case-insensitive
//  (localizedStandardContains), so "cafe" finds "Café".
//
//  Rendered as a List so rows get swipe actions; rows also carry the
//  shared item context menu.
//

import SwiftUI
import SwiftData

struct SearchResultsView: View {
    let searchText: String
    /// Host presents its own ItemDetailSheet — sheet state stays with the tab.
    let onSelectItem: (Item) -> Void
    /// Called after a Browse deep-link is triggered so the host can dismiss search.
    var onNavigate: () -> Void = {}

    @Query private var allItems: [Item]
    @Query(sort: \Location.dateCreated) private var allLocations: [Location]
    @Environment(NavigationState.self) private var navState
    @Environment(\.modelContext) private var modelContext

    @State private var itemToMove: Item? = nil
    @State private var pickerExpandedIDs: Set<UUID> = []
    @State private var itemToDelete: Item? = nil
    @State private var showDeleteAlert = false

    // MARK: Filtering

    /// Items whose own name or notes field matches — location name is intentionally
    /// excluded so location matches surface only in the Spaces section.
    private var filteredItems: [Item] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return allItems.filter { item in
            item.name.localizedStandardContains(q) ||
            (item.notes?.localizedStandardContains(q) == true)
        }
    }

    /// Locations whose name matches the query.
    private var filteredLocations: [Location] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return allLocations
            .filter { $0.name.localizedStandardContains(q) }
            .sorted { $0.name < $1.name }
    }

    // MARK: Body

    var body: some View {
        let items     = filteredItems
        let locations = filteredLocations

        Group {
            if items.isEmpty && locations.isEmpty {
                VStack {
                    Spacer()
                    Text("No results for \"\(searchText)\"")
                        .foregroundStyle(Color(.secondaryLabel))
                        .multilineTextAlignment(.center)
                        .padding()
                    Spacer()
                }
            } else {
                List {
                    if !items.isEmpty {
                        Section {
                            ForEach(items) { item in
                                SearchResultRow(
                                    item: item,
                                    onTap: { onSelectItem(item) },
                                    onLocationTap: { navigateTo(item.location) }
                                )
                                .contextMenu {
                                    ItemContextMenuContent(
                                        item: item,
                                        onMove: { itemToMove = item },
                                        onDelete: { requestDelete(item) }
                                    )
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    OutOfPlaceSwipeButton(item: item)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) { requestDelete(item) }
                                        label: { Label("Delete", systemImage: "trash") }
                                }
                            }
                        } header: {
                            SectionHeader(title: "Items", level: .secondary)
                        }
                    }

                    if !locations.isEmpty {
                        Section {
                            ForEach(locations) { location in
                                SearchLocationRow(location: location) {
                                    navigateTo(location)
                                }
                            }
                        } header: {
                            SectionHeader(title: "Spaces", level: .secondary)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .sheet(item: $itemToMove) { item in
            LocationPickerSheet(
                title: "Move to…",
                excludedIDs: [],
                allowTopLevel: false,
                expandedIDs: $pickerExpandedIDs,
                onSelect: { newLocation in
                    if let loc = newLocation {
                        item.location = loc
                        item.lastVerified = Date()
                    }
                }
            )
        }
        .alert("Delete \"\(itemToDelete?.name ?? "")\"?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let item = itemToDelete {
                    Haptics.write()
                    modelContext.delete(item)
                    itemToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }

    // MARK: Actions

    private func requestDelete(_ item: Item) {
        itemToDelete = item
        showDeleteAlert = true
    }

    /// Deep-links into the Browse tab at the given location, building the full ancestor chain.
    private func navigateTo(_ location: Location?) {
        guard let location else { return }
        navState.browseNavigationPath = location.ancestorChain
        navState.selectedTab = 1
        onNavigate()
    }
}

// MARK: - Shared item context menu

/// The long-press fast path for an item row, used in Browse and search results.
/// All mutations go through the Item model methods.
struct ItemContextMenuContent: View {
    let item: Item
    let onMove: () -> Void
    let onDelete: () -> Void

    var body: some View {
        // Increment/decrement only when quantity tracking is on — incrementing
        // an untracked item would silently switch tracking on.
        if let qty = item.quantity {
            Button { Haptics.write(); item.incrementQuantity() } label: {
                Label("Add One", systemImage: "plus.circle")
            }
            Button { Haptics.write(); item.decrementQuantity() } label: {
                Label("Remove One", systemImage: "minus.circle")
            }
            .disabled(qty == 0)
        }

        Button { Haptics.write(); item.markAsVerified() } label: {
            Label("Mark as Verified", systemImage: "checkmark.circle")
        }

        Button {
            Haptics.write()
            if item.isOutOfPlace {
                item.returnToPlace()
            } else {
                item.isOutOfPlace = true
            }
        } label: {
            if item.isOutOfPlace {
                Label("Return to Place", systemImage: "arrow.down.circle")
            } else {
                Label("Out of Place", systemImage: "arrow.up.right.square")
            }
        }

        Button(action: onMove) {
            Label("Move…", systemImage: "arrow.up.arrow.down")
        }

        Divider()

        Button(role: .destructive, action: onDelete) {
            Label("Delete", systemImage: "trash")
        }
    }
}

// MARK: - Out of place swipe button

/// Leading swipe toggle shared by Browse and search item rows.
struct OutOfPlaceSwipeButton: View {
    let item: Item

    var body: some View {
        Button {
            Haptics.write()
            if item.isOutOfPlace {
                item.returnToPlace()
            } else {
                item.isOutOfPlace = true
            }
        } label: {
            if item.isOutOfPlace {
                Label("Return to Place", systemImage: "arrow.down.circle.fill")
            } else {
                Label("Out of Place", systemImage: "arrow.up.right.square")
            }
        }
        // Marking out of place uses the shared indigo (C1); returning is teal.
        .tint(item.isOutOfPlace ? .teal : StatusColor.outOfPlace.color)
    }
}

// MARK: - Search location row

struct SearchLocationRow: View {
    let location: Location
    let onTap: () -> Void

    private var areaColor: Color {
        rootAreaColor(for: location) ?? .teal
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                LocationIconView(
                    icon: location.icon ?? "folder.fill",
                    font: .body,
                    color: location.icon != nil ? areaColor : Color(.secondaryLabel)
                )
                .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(location.name)
                        .font(.headline)
                        .foregroundStyle(Color(.label))
                    if !ancestorPath.isEmpty {
                        Text(ancestorPath)
                            .font(.caption)
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Full path of ancestors above this location, e.g. "Kitchen › Cupboards".
    /// Empty if this is a root area.
    private var ancestorPath: String {
        location.ancestorChain.dropLast().map(\.name).joined(separator: " › ")
    }
}
