//
//  BrowseTab.swift
//  Stash
//
//  Root of the Browse tab. Shows all top-level Areas and owns the NavigationStack
//  path that every BrowseLocationView shares for breadcrumb navigation.
//

import SwiftUI
import SwiftData

struct BrowseTab: View {
    // Load all locations; filter roots in a computed property to avoid
    // predicate compilation issues with optional relationship comparisons.
    @Query(sort: \Location.dateCreated) private var allLocations: [Location]
    @Environment(\.modelContext) private var modelContext
    @Environment(NavigationState.self) private var navState
    @State private var showAddLocation = false
    @State private var locationToEdit: Location? = nil
    @State private var selectedItem: Item? = nil
    @State private var searchText = ""

    // Reorder mode for the root Areas list.
    @State private var editMode: EditMode = .inactive

    // Delete state
    @State private var locationToDelete: Location? = nil
    @State private var showDeleteActionSheet = false
    @State private var showCascadeConfirm = false
    @State private var showEmptyDeleteAlert = false

    private var rootAreas: [Location] {
        allLocations.filter { $0.parent == nil }
    }

    /// Root Areas in display order: manual `sortOrder` once the user has
    /// reordered, otherwise creation order (the @Query's dateCreated sort),
    /// which also acts as the tiebreaker for not-yet-ordered Areas.
    private var sortedRootAreas: [Location] {
        let list = rootAreas
        guard list.contains(where: { $0.sortOrder > 0 }) else { return list }
        return list.sorted { a, b in
            if a.sortOrder == 0 && b.sortOrder == 0 { return a.dateCreated < b.dateCreated }
            if a.sortOrder == 0 { return false }
            if b.sortOrder == 0 { return true }
            return a.sortOrder < b.sortOrder
        }
    }

    var body: some View {
        @Bindable var bindableNavState = navState
        NavigationStack(path: $bindableNavState.browseNavigationPath) {
            Group {
                if !searchText.isEmpty {
                    SearchResultsView(
                        searchText: searchText,
                        onSelectItem: { selectedItem = $0 },
                        onNavigate: { searchText = "" }
                    )
                } else {
                    rootList
                }
            }
            .navigationTitle("Browse")
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: "Search items, spaces, notes…"
            )
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if editMode.isEditing {
                        Button("Done") { withAnimation { editMode = .inactive } }
                    } else {
                        addMenu
                    }
                }
            }
            .navigationDestination(for: Location.self) { location in
                BrowseLocationView(location: location, navigationPath: $bindableNavState.browseNavigationPath)
            }
        }
        // MARK: Intent search handoff (SearchStashIntent)
        // "Search Stash for…" posts the query to IntentRouter; ContentView
        // switches to this tab and we run it in the root search field.
        .onChange(of: IntentRouter.shared.pendingSearchText) { consumePendingIntentSearch() }
        .onAppear { consumePendingIntentSearch() }
        // MARK: Sheets
        .sheet(isPresented: $showAddLocation) { AddLocationSheet(parentLocation: nil) }
        .sheet(item: $locationToEdit)         { LocationDetailSheet(location: $0) }
        .sheet(item: $selectedItem)           { ItemDetailSheet(item: $0) }
        // MARK: Delete — non-empty
        .confirmationDialog(
            "Delete \"\(locationToDelete?.name ?? "")\"?",
            isPresented: $showDeleteActionSheet,
            titleVisibility: .visible
        ) {
            Button("Delete everything inside", role: .destructive) {
                showCascadeConfirm = true
            }
            Button("Move contents to Top Level") {
                if let loc = locationToDelete {
                    moveContentsToRoot(of: loc)
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
        // MARK: Delete — empty
        .alert("Delete \"\(locationToDelete?.name ?? "")\"?",
               isPresented: $showEmptyDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let loc = locationToDelete {
                    Haptics.write()
                    modelContext.delete(loc)
                    locationToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This cannot be undone.") }
    }

    // MARK: - Toolbar menu

    /// A single tap opens the menu. Only Add Space and Reorder Spaces make
    /// sense at the root — Quick Add, Add Item and Add Photo are location-only.
    private var addMenu: some View {
        Menu {
            Button { showAddLocation = true } label: {
                Label("Add Space", systemImage: "folder.badge.plus")
            }
            if rootAreas.count > 1 {
                Button { withAnimation { editMode = .active } } label: {
                    Label("Reorder Spaces", systemImage: "arrow.up.arrow.down")
                }
            }
        } label: {
            Image(systemName: "plus")
        }
    }

    // MARK: - Root list

    private var rootList: some View {
        List {
            ForEach(sortedRootAreas) { area in
                NavigationLink(value: area) {
                    LocationRow(location: area)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) { requestDelete(area) }
                        label: { Label("Delete", systemImage: "trash") }
                    Button { locationToEdit = area }
                        label: { Label("Edit", systemImage: "pencil") }
                        .tint(.teal)
                }
            }
            .onMove { indices, destination in
                var ordered = sortedRootAreas
                ordered.move(fromOffsets: indices, toOffset: destination)
                for (index, area) in ordered.enumerated() {
                    area.sortOrder = index + 1
                }
            }
        }
        .environment(\.editMode, $editMode)
        .overlay {
            if rootAreas.isEmpty {
                ContentUnavailableView {
                    Label("No Spaces Yet", systemImage: "archivebox")
                } description: {
                    Text("Tap + to add your first area.")
                }
            }
        }
    }

    // MARK: - Helpers

    /// Runs a search handed over from SearchStashIntent, popping back to the
    /// Browse root first so the results appear in the root search field.
    private func consumePendingIntentSearch() {
        guard let text = IntentRouter.shared.pendingSearchText else { return }
        IntentRouter.shared.pendingSearchText = nil
        navState.browseNavigationPath = []
        searchText = text
    }

    private func requestDelete(_ location: Location) {
        locationToDelete = location
        if location.childList.isEmpty && location.itemList.isEmpty {
            showEmptyDeleteAlert = true
        } else {
            showDeleteActionSheet = true
        }
    }

    private func cascadeDelete(_ loc: Location) {
        modelContext.cascadeDelete(loc)
    }

    private func moveContentsToRoot(of loc: Location) {
        for child in loc.childList { child.parent = nil }
        // Items can't live at the top level — a nil location makes them
        // invisible in the tree. Park them in the "Unsorted" Area instead.
        let items = loc.itemList
        if !items.isEmpty {
            let unsorted = Location.unsortedArea(in: modelContext, excluding: loc.id)
            for item in items { item.location = unsorted }
        }
        modelContext.delete(loc)
    }
}
