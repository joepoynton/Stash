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

    // Delete state
    @State private var locationToDelete: Location? = nil
    @State private var showDeleteActionSheet = false
    @State private var showCascadeConfirm = false
    @State private var showEmptyDeleteAlert = false

    private var rootAreas: [Location] {
        allLocations.filter { $0.parent == nil }
    }

    var body: some View {
        @Bindable var bindableNavState = navState
        NavigationStack(path: $bindableNavState.browseNavigationPath) {
            List {
                ForEach(rootAreas) { area in
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
            }
            .navigationTitle("Browse")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAddLocation = true } label: { Image(systemName: "plus") }
                }
            }
            .overlay {
                if rootAreas.isEmpty {
                    ContentUnavailableView {
                        Label("No Spaces Yet", systemImage: "archivebox")
                    } description: {
                        Text("Tap + to add your first area.")
                    }
                }
            }
            .navigationDestination(for: Location.self) { location in
                BrowseLocationView(location: location, navigationPath: $bindableNavState.browseNavigationPath)
            }
        }
        // MARK: Sheets
        .sheet(isPresented: $showAddLocation) { AddLocationSheet(parentLocation: nil) }
        .sheet(item: $locationToEdit)         { LocationDetailSheet(location: $0) }
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
                    modelContext.delete(loc)
                    locationToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This cannot be undone.") }
    }

    // MARK: - Helpers

    private func requestDelete(_ location: Location) {
        locationToDelete = location
        if location.childList.isEmpty && location.itemList.isEmpty {
            showEmptyDeleteAlert = true
        } else {
            showDeleteActionSheet = true
        }
    }

    private func cascadeDelete(_ loc: Location) {
        for child in loc.childList { cascadeDelete(child) }
        modelContext.delete(loc)
    }

    private func moveContentsToRoot(of loc: Location) {
        for child in loc.childList { child.parent  = nil }
        for item  in loc.itemList  { item.location = nil }
        modelContext.delete(loc)
    }
}
