//
//  BrowseLocationView.swift
//  Stash
//
//  One screen in the Browse navigation stack. Shows child Locations ("Spaces")
//  and Items for the given location, with a tappable breadcrumb in the toolbar.
//
//  "+" is the fast path: a single tap opens Quick Add; the full menu
//  (Add Space, Add Item, Add Photo, Reorder) sits behind a long-press.
//

import SwiftUI
import SwiftData

// MARK: - Item sort mode (F9)

enum BrowseItemSort: String, CaseIterable, Identifiable {
    case alphabetical
    case lowStockFirst
    case recentlyAdded

    var id: String { rawValue }

    var label: String {
        switch self {
        case .alphabetical:  "Alphabetical"
        case .lowStockFirst: "Low stock first"
        case .recentlyAdded: "Recently added"
        }
    }
}

struct BrowseLocationView: View {
    let location: Location
    @Binding var navigationPath: [Location]

    @Environment(\.modelContext) private var modelContext
    @Environment(StoreKitManager.self) private var storeKit
    @Environment(NavigationState.self) private var navState
    @Query private var allItems: [Item]

    // Sheet / dialog state
    @State private var activeSheet: BrowseSheet? = nil
    @State private var showPhotoUpgradePrompt = false
    @State private var showItemLimitPrompt = false
    @State private var pickerExpandedIDs: Set<UUID> = []

    // Search
    @State private var searchText = ""

    // Item sort — shared across all Browse screens
    @AppStorage("browseItemSort") private var itemSortRaw = BrowseItemSort.alphabetical.rawValue

    // F11: one-time long-press discovery tip. Global flag — shows on the first
    // Browse screen that has items, then never again (dismissed or long-press used).
    @AppStorage("browseCoachMarkSeen") private var coachMarkSeen = false

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

    private var itemSort: BrowseItemSort {
        BrowseItemSort(rawValue: itemSortRaw) ?? .alphabetical
    }

    private var sortedItems: [Item] {
        let list = location.itemList
        switch itemSort {
        case .alphabetical:
            return list.sorted { $0.name < $1.name }
        case .lowStockFirst:
            return list.sorted { a, b in
                let aLow = a.orderStatus == .low
                let bLow = b.orderStatus == .low
                if aLow != bLow { return aLow }
                return a.name < b.name
            }
        case .recentlyAdded:
            return list.sorted { $0.dateAdded > $1.dateAdded }
        }
    }

    private var ancestorChain: [Location] {
        location.ancestorChain
    }

    /// Free tier at (or over) the item cap — adding must show the paywall, not the form.
    private var atFreeLimit: Bool {
        !storeKit.isPro && allItems.count >= FeatureFlags.freeItemLimit
    }

    // MARK: - Body

    var body: some View {
        let children = sortedChildren
        let items    = sortedItems
        let mixed    = !children.isEmpty && !items.isEmpty

        Group {
            if !searchText.isEmpty {
                SearchResultsView(
                    searchText: searchText,
                    onSelectItem: { activeSheet = .itemDetail($0) },
                    onNavigate: { searchText = "" }
                )
            } else {
                listContent(children: children, items: items, mixed: mixed)
            }
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "Search items, spaces, notes…"
        )
        .tint(areaTint)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { breadcrumbHeader }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if editMode.isEditing {
                    Button("Done") {
                        withAnimation { editMode = .inactive }
                    }
                } else {
                    if location.itemList.count > 1 {
                        sortMenu
                    }
                    addMenu
                }
            }
        }
        .onAppear {
            // Deep-link from an Area card's "Reorder Spaces" context action.
            if navState.pendingReorderLocationID == location.id {
                navState.pendingReorderLocationID = nil
                withAnimation { editMode = .active }
            }
        }
        .modifier(BrowseLocationSheets(
            location: location,
            activeSheet: $activeSheet,
            pickerExpandedIDs: $pickerExpandedIDs,
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
        .sheet(isPresented: $showItemLimitPrompt) {
            UpgradePromptSheet(
                message: "You've used \(allItems.count) of \(FeatureFlags.freeItemLimit) free items. Unlock Stash Pro for unlimited items, photos, and data export."
            )
        }
    }

    // MARK: - Toolbar menus

    /// Tap = Quick Add (the highest-frequency action); long-press = full menu.
    private var addMenu: some View {
        Menu {
            Button { activeSheet = .addLocation } label: {
                Label("Add Space", systemImage: "folder.badge.plus")
            }
            Button { presentAddItem() } label: {
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
        } primaryAction: {
            presentQuickAdd()
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort items", selection: $itemSortRaw) {
                ForEach(BrowseItemSort.allCases) { mode in
                    Text(mode.label).tag(mode.rawValue)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
    }

    // MARK: - Free-tier gate (U9): paywall at presentation, not after the form

    private func presentQuickAdd() {
        if atFreeLimit { showItemLimitPrompt = true } else { activeSheet = .quickAdd }
    }

    private func presentAddItem() {
        if atFreeLimit { showItemLimitPrompt = true } else { activeSheet = .addItem }
    }

    @ViewBuilder
    private func listContent(children: [Location], items: [Item], mixed: Bool) -> some View {
        List {
            if !coachMarkSeen && !items.isEmpty {
                coachMark
            }
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
                    Button("+ Add your first item") { presentAddItem() }
                        .buttonStyle(.bordered)
                        .tint(areaTint)
                }
            }
        }
    }

    // MARK: - Coach mark (F11)

    private var coachMark: some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: "hand.tap.fill")
                    .foregroundStyle(areaTint)
                Text("Tip: touch and hold any item for quick actions.")
                    .font(.subheadline)
                    .foregroundStyle(Color(.label))
                Spacer(minLength: 8)
                Button {
                    withAnimation { coachMarkSeen = true }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.bold())
                        .foregroundStyle(Color(.secondaryLabel))
                }
                .buttonStyle(.plain)
            }
            .listRowBackground(areaTint.opacity(0.12))
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
            .contextMenu {
                ItemContextMenuContent(
                    item: item,
                    onMove: { activeSheet = .itemMove(item) },
                    onDelete: {
                        itemToDelete = item
                        showItemDeleteAlert = true
                    }
                )
            }
            // Once the user discovers the long-press, retire the coach mark.
            // simultaneousGesture runs alongside the context menu without
            // consuming the press, so quick actions still open normally.
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                    if !coachMarkSeen { coachMarkSeen = true }
                }
            )
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                OutOfPlaceSwipeButton(item: item)
            }
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

// MARK: - Sheet enum

private enum BrowseSheet: Identifiable, Equatable {
    static func == (lhs: BrowseSheet, rhs: BrowseSheet) -> Bool { lhs.id == rhs.id }
    case addItem
    case addLocation
    case quickAdd
    case itemDetail(Item)
    case itemMove(Item)
    case locationEdit(Location)
    case locationPhotoOptions
    case photosPicker

    var id: String {
        switch self {
        case .addItem:                   return "addItem"
        case .addLocation:               return "addLocation"
        case .quickAdd:                  return "quickAdd"
        case .itemDetail(let item):      return "itemDetail-\(item.id)"
        case .itemMove(let item):        return "itemMove-\(item.id)"
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
    @Binding var pickerExpandedIDs: Set<UUID>
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
                case .itemMove(let item):
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
                case .locationEdit(let loc): LocationDetailSheet(location: loc)
                case .locationPhotoOptions:  EmptyView()
                case .photosPicker:          EmptyView()
                }
            }
            .confirmationDialog("Photo", isPresented: $showLocationPhotoActions, titleVisibility: .hidden) {
                Button("Take Photo") { showCamera = true }
                Button("Choose from Library") { showLibraryPicker = true }
                if location.photo != nil {
                    Button("Remove Photo", role: .destructive) {
                        location.photo = nil
                        ThumbnailCache.shared.invalidate(id: location.id)
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraView { data in
                    Task {
                        if let compressed = await ImageCompressor.compress(data) {
                            location.photo = compressed
                            ThumbnailCache.shared.invalidate(id: location.id)
                        }
                    }
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showLibraryPicker) {
                LibraryPickerView { data in
                    Task {
                        if let compressed = await ImageCompressor.compress(data) {
                            location.photo = compressed
                            ThumbnailCache.shared.invalidate(id: location.id)
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
                        Haptics.write()
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
                        Haptics.write()
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
                        Haptics.write()
                        modelContext.delete(item)
                        itemToDelete = nil
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("This cannot be undone.") }
    }
}
