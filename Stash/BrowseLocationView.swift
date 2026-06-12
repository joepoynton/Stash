//
//  BrowseLocationView.swift
//  Stash
//
//  One screen in the Browse navigation stack. Shows child Locations ("Spaces")
//  and Items for the given location, with a tappable breadcrumb in the toolbar.
//

import SwiftUI
import SwiftData

struct BrowseLocationView: View {
    let location: Location
    @Binding var navigationPath: [Location]

    @Environment(\.modelContext) private var modelContext
    @Environment(StoreKitManager.self) private var storeKit

    // Sheet / dialog state
    @State private var activeSheet: BrowseSheet? = nil
    @State private var showPhotoUpgradePrompt = false

    // Location delete state
    @State private var locationToDelete: Location? = nil
    @State private var showLocationDeleteActionSheet = false
    @State private var showCascadeConfirm = false
    @State private var showEmptyLocationDeleteAlert = false

    // Item delete state
    @State private var itemToDelete: Item? = nil
    @State private var showItemDeleteAlert = false

    // Location photo state
    @State private var showCamera = false
    @State private var showLibraryPicker = false
    @State private var showLocationPhotoActions = false

    // Reorder mode
    @State private var editMode: EditMode = .inactive

    // MARK: - Area tint

    /// Walks up to the root ancestor and returns its colour, falling back to teal.
    private var areaTint: Color {
        rootAreaColor(for: location) ?? .teal
    }

    // MARK: - Derived data

    private var sortedChildren: [Location] {
        let list = location.childList
        // If any child has been manually ordered (sortOrder > 0), use manual order.
        // New locations (sortOrder == 0) sort alphabetically after ordered items.
        guard list.contains(where: { $0.sortOrder > 0 }) else {
            return list.sorted { $0.name < $1.name }
        }
        return list.sorted { a, b in
            if a.sortOrder == 0 && b.sortOrder == 0 { return a.name < b.name }
            if a.sortOrder == 0 { return false }
            if b.sortOrder == 0 { return true }
            return a.sortOrder < b.sortOrder
        }
    }

    private var sortedItems: [Item] {
        location.itemList.sorted { $0.name < $1.name }
    }

    private var ancestorChain: [Location] {
        location.ancestorChain
    }

    // MARK: - Body

    var body: some View {
        let children = sortedChildren
        let items    = sortedItems
        let mixed    = !children.isEmpty && !items.isEmpty

        listContent(children: children, items: items, mixed: mixed)
            .tint(areaTint)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { breadcrumbHeader }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if editMode.isEditing {
                        Button("Done") {
                            withAnimation { editMode = .inactive }
                        }
                    } else {
                        Menu {
                            Button { activeSheet = .quickAdd } label: {
                                Label("Quick Add", systemImage: "bolt")
                            }
                            Button { activeSheet = .addLocation } label: {
                                Label("Add Space", systemImage: "folder.badge.plus")
                            }
                            Button { activeSheet = .addItem } label: {
                                Label("Add Item", systemImage: "plus.square")
                            }
                            Button {
                                if storeKit.isPro {
                                    showLocationPhotoActions = true
                                } else {
                                    showPhotoUpgradePrompt = true
                                }
                            } label: {
                                Label(
                                    location.photo != nil ? "Replace Photo" : "Add Photo",
                                    systemImage: storeKit.isPro ? "camera" : "lock.fill"
                                )
                            }
                            if !location.childList.isEmpty {
                                Button {
                                    withAnimation { editMode = .active }
                                } label: {
                                    Label("Reorder Spaces", systemImage: "arrow.up.arrow.down")
                                }
                            }
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .modifier(BrowseLocationSheets(
                location: location,
                activeSheet: $activeSheet,
                showCamera: $showCamera,
                showLibraryPicker: $showLibraryPicker,
                showLocationPhotoActions: $showLocationPhotoActions,
                locationToDelete: $locationToDelete,
                showLocationDeleteActionSheet: $showLocationDeleteActionSheet,
                showCascadeConfirm: $showCascadeConfirm,
                showEmptyLocationDeleteAlert: $showEmptyLocationDeleteAlert,
                itemToDelete: $itemToDelete,
                showItemDeleteAlert: $showItemDeleteAlert,
                moveContentsToParent: moveContentsToParent,
                cascadeDelete: cascadeDelete,
                modelContext: modelContext
            ))
            .sheet(isPresented: $showPhotoUpgradePrompt) {
                UpgradePromptSheet(message: "Unlock Stash Pro to add photos to your items and locations.")
            }
    }

    @ViewBuilder
    private func listContent(children: [Location], items: [Item], mixed: Bool) -> some View {
        List {
            if mixed {
                Section("Spaces") { locationRows(children) }
                Section("Items")  { itemRows(items) }
            } else {
                locationRows(children)
                itemRows(items)
            }
        }
        .environment(\.editMode, $editMode)
        .overlay {
            if children.isEmpty && items.isEmpty {
                ContentUnavailableView {
                    Label("Empty Space", systemImage: "tray")
                } description: {
                    Text("No items or sub-spaces here yet.")
                } actions: {
                    Button("+ Add your first item") { activeSheet = .addItem }
                        .buttonStyle(.bordered)
                        .tint(areaTint)
                }
            }
        }
    }

    // MARK: - Row builders

    @ViewBuilder
    private func locationRows(_ children: [Location]) -> some View {
        ForEach(children) { child in
            NavigationLink(value: child) {
                LocationRow(location: child)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) { requestDeleteLocation(child) }
                    label: { Label("Delete", systemImage: "trash") }
                    .tint(.red)
                Button { activeSheet = .locationEdit(child) }
                    label: { Label("Edit", systemImage: "pencil") }
                    .tint(.teal)
            }
        }
        .onMove { indices, destination in
            var ordered = children
            ordered.move(fromOffsets: indices, toOffset: destination)
            for (index, child) in ordered.enumerated() {
                child.sortOrder = index + 1
            }
        }
    }

    @ViewBuilder
    private func itemRows(_ items: [Item]) -> some View {
        ForEach(items) { item in
            Button { activeSheet = .itemDetail(item) } label: {
                ItemRow(item: item)
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    itemToDelete = item
                    showItemDeleteAlert = true
                } label: { Label("Delete", systemImage: "trash") }
                    .tint(.red)
                Button { activeSheet = .itemDetail(item) }
                    label: { Label("Edit", systemImage: "pencil") }
                    .tint(.teal)
            }
        }
    }

    // MARK: - Breadcrumb toolbar view

    private var breadcrumbHeader: some View {
        VStack(spacing: 1) {
            Text(location.name)
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(Array(ancestorChain.enumerated()), id: \.element.id) { idx, ancestor in
                        if idx > 0 {
                            Text("›")
                                .font(.caption2)
                                .foregroundStyle(Color(.tertiaryLabel))
                        }
                        Button {
                            navigateTo(ancestor)
                        } label: {
                            Text(ancestor.name)
                                .font(.caption2)
                                .foregroundStyle(
                                    ancestor.id == location.id ? Color(.label) : areaTint
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Navigation

    private func navigateTo(_ target: Location) {
        guard let idx = navigationPath.firstIndex(where: { $0.id == target.id }) else { return }
        navigationPath = Array(navigationPath.prefix(through: idx))
    }

    // MARK: - Delete logic

    private func requestDeleteLocation(_ loc: Location) {
        locationToDelete = loc
        if loc.childList.isEmpty && loc.itemList.isEmpty {
            showEmptyLocationDeleteAlert = true
        } else {
            showLocationDeleteActionSheet = true
        }
    }

    private func cascadeDelete(_ loc: Location) {
        modelContext.cascadeDelete(loc)
    }

    private func moveContentsToParent(of loc: Location) {
        let dest = loc.parent
        for child in loc.childList { child.parent   = dest }
        for item  in loc.itemList  { item.location  = dest }
        modelContext.delete(loc)
    }
}

// MARK: - Quick Add Sheet

private struct QuickAddSheet: View {
    let location: Location

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(StoreKitManager.self) private var storeKit
    @Query private var allItems: [Item]

    @State private var name = ""
    @State private var addedItems: [Item] = []
    @State private var itemToDetail: Item? = nil
    @State private var showUpgradePrompt = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                TextField("Item name", text: $name)
                    .font(.body)
                    .padding()
                    .focused($focused)
                    .onSubmit { saveAndClear() }
                    .submitLabel(.return)

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
            .onAppear { focused = true }
            .sheet(item: $itemToDetail, onDismiss: { focused = true }) {
                ItemDetailSheet(item: $0)
            }
            .sheet(isPresented: $showUpgradePrompt, onDismiss: { focused = true }) {
                UpgradePromptSheet(
                    message: "You've used \(allItems.count) of \(FeatureFlags.freeItemLimit) free items. Unlock Stash Pro for unlimited items, photos, and data export."
                )
            }
        }
    }

    private func saveAndClear() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        guard storeKit.isPro || allItems.count < FeatureFlags.freeItemLimit else {
            focused = false
            showUpgradePrompt = true
            return
        }
        let item = Item(name: trimmed, location: location)
        modelContext.insert(item)
        addedItems.insert(item, at: 0)   // newest at top
        name = ""
        focused = true
    }
}

// MARK: - Sheet enum

private enum BrowseSheet: Identifiable, Equatable {
    static func == (lhs: BrowseSheet, rhs: BrowseSheet) -> Bool { lhs.id == rhs.id }
    case addItem
    case addLocation
    case quickAdd
    case itemDetail(Item)
    case locationEdit(Location)
    case locationPhotoOptions
    case photosPicker

    var id: String {
        switch self {
        case .addItem:                   return "addItem"
        case .addLocation:               return "addLocation"
        case .quickAdd:                  return "quickAdd"
        case .itemDetail(let item):      return "itemDetail-\(item.id)"
        case .locationEdit(let loc):     return "locationEdit-\(loc.id)"
        case .locationPhotoOptions:      return "locationPhotoOptions"
        case .photosPicker:              return "photosPicker"
        }
    }
}

// MARK: - Sheet / alert modifier (extracted to help the compiler type-check BrowseLocationView.body)

private struct BrowseLocationSheets: ViewModifier {
    let location: Location
    @Binding var activeSheet: BrowseSheet?
    @Binding var showCamera: Bool
    @Binding var showLibraryPicker: Bool
    @Binding var showLocationPhotoActions: Bool
    @Binding var locationToDelete: Location?
    @Binding var showLocationDeleteActionSheet: Bool
    @Binding var showCascadeConfirm: Bool
    @Binding var showEmptyLocationDeleteAlert: Bool
    @Binding var itemToDelete: Item?
    @Binding var showItemDeleteAlert: Bool
    let moveContentsToParent: (Location) -> Void
    let cascadeDelete: (Location) -> Void
    let modelContext: ModelContext

    func body(content: Content) -> some View {
        let withAlerts = content.modifier(BrowseLocationAlerts(
            locationToDelete: $locationToDelete,
            showLocationDeleteActionSheet: $showLocationDeleteActionSheet,
            showCascadeConfirm: $showCascadeConfirm,
            showEmptyLocationDeleteAlert: $showEmptyLocationDeleteAlert,
            itemToDelete: $itemToDelete,
            showItemDeleteAlert: $showItemDeleteAlert,
            moveContentsToParent: moveContentsToParent,
            cascadeDelete: cascadeDelete,
            modelContext: modelContext
        ))
        withAlerts
            // MARK: Single sheet presenter
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .addItem:               AddItemSheet(location: location)
                case .addLocation:           AddLocationSheet(parentLocation: location)
                case .quickAdd:              QuickAddSheet(location: location)
                case .itemDetail(let item):  ItemDetailSheet(item: item)
                case .locationEdit(let loc): LocationDetailSheet(location: loc)
                case .locationPhotoOptions:  EmptyView()
                case .photosPicker:          EmptyView()
                }
            }
            .confirmationDialog("Photo", isPresented: $showLocationPhotoActions, titleVisibility: .hidden) {
                Button("Take Photo") { showCamera = true }
                Button("Choose from Library") { showLibraryPicker = true }
                if location.photo != nil {
                    Button("Remove Photo", role: .destructive) { location.photo = nil }
                }
                Button("Cancel", role: .cancel) {}
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraView { data in
                    Task {
                        let image = UIImage(data: data)
                        let compressed = image.flatMap { ImageCompressor.compress($0) }
                        await MainActor.run {
                            if let compressed { location.photo = compressed }
                        }
                    }
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showLibraryPicker) {
                LibraryPickerView { data in
                    Task {
                        let image = UIImage(data: data)
                        let compressed = image.flatMap { ImageCompressor.compress($0) }
                        await MainActor.run {
                            if let compressed { location.photo = compressed }
                        }
                    }
                }
                .ignoresSafeArea()
            }
    }
}

// MARK: - Delete alert modifier

private struct BrowseLocationAlerts: ViewModifier {
    @Binding var locationToDelete: Location?
    @Binding var showLocationDeleteActionSheet: Bool
    @Binding var showCascadeConfirm: Bool
    @Binding var showEmptyLocationDeleteAlert: Bool
    @Binding var itemToDelete: Item?
    @Binding var showItemDeleteAlert: Bool
    let moveContentsToParent: (Location) -> Void
    let cascadeDelete: (Location) -> Void
    let modelContext: ModelContext

    func body(content: Content) -> some View {
        content
            // MARK: Location delete — non-empty
            .confirmationDialog(
                "Delete \"\(locationToDelete?.name ?? "")\"?",
                isPresented: $showLocationDeleteActionSheet,
                titleVisibility: .visible
            ) {
                Button("Delete everything inside", role: .destructive) {
                    showCascadeConfirm = true
                }
                if let loc = locationToDelete {
                    Button("Move contents to \(loc.parent?.name ?? "Top Level")") {
                        moveContentsToParent(loc)
                        locationToDelete = nil
                    }
                }
                Button("Cancel", role: .cancel) { locationToDelete = nil }
            }
            .alert("Are you sure?", isPresented: $showCascadeConfirm) {
                Button("Delete everything", role: .destructive) {
                    if let loc = locationToDelete {
                        cascadeDelete(loc)
                        locationToDelete = nil
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone.")
            }
            // MARK: Location delete — empty
            .alert("Delete \"\(locationToDelete?.name ?? "")\"?",
                   isPresented: $showEmptyLocationDeleteAlert) {
                Button("Delete", role: .destructive) {
                    if let loc = locationToDelete {
                        modelContext.delete(loc)
                        locationToDelete = nil
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("This cannot be undone.") }
            // MARK: Item delete
            .alert("Delete \"\(itemToDelete?.name ?? "")\"?",
                   isPresented: $showItemDeleteAlert) {
                Button("Delete", role: .destructive) {
                    if let item = itemToDelete {
                        modelContext.delete(item)
                        itemToDelete = nil
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("This cannot be undone.") }
    }
}
