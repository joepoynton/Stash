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

    // Sheet / dialog state
    @State private var showAddActionSheet = false
    @State private var addingItem = false
    @State private var addingLocation = false
    @State private var itemToShow: Item? = nil
    @State private var locationToEdit: Location? = nil

    // Location delete state
    @State private var locationToDelete: Location? = nil
    @State private var showLocationDeleteActionSheet = false
    @State private var showCascadeConfirm = false
    @State private var showEmptyLocationDeleteAlert = false

    // Item delete state
    @State private var itemToDelete: Item? = nil
    @State private var showItemDeleteAlert = false

    // MARK: - Derived data

    private var sortedChildren: [Location] {
        location.childList.sorted { $0.name < $1.name }
    }

    private var sortedItems: [Item] {
        location.itemList.sorted { $0.name < $1.name }
    }

    private var ancestorChain: [Location] {
        var chain: [Location] = []
        var current: Location? = location
        while let loc = current {
            chain.insert(loc, at: 0)
            current = loc.parent
        }
        return chain
    }

    // MARK: - Body

    var body: some View {
        let children = sortedChildren
        let items    = sortedItems
        let mixed    = !children.isEmpty && !items.isEmpty

        List {
            if mixed {
                Section("Spaces") { locationRows(children) }
                Section("Items")  { itemRows(items) }
            } else {
                locationRows(children)
                itemRows(items)
            }
        }
        .overlay {
            if children.isEmpty && items.isEmpty {
                ContentUnavailableView {
                    Label("Empty Space", systemImage: "tray")
                } description: {
                    Text("No items or sub-spaces here yet.")
                } actions: {
                    Button("+ Add your first item") { addingItem = true }
                        .buttonStyle(.bordered)
                        .tint(.teal)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { breadcrumbHeader }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showAddActionSheet = true } label: { Image(systemName: "plus") }
            }
        }
        // MARK: Add action sheet
        .confirmationDialog("Add", isPresented: $showAddActionSheet) {
            Button("Add Space") { addingLocation = true }
            Button("Add Item")  { addingItem     = true }
            Button("Cancel", role: .cancel) {}
        }
        // MARK: Sheets
        .sheet(isPresented: $addingItem)     { AddItemSheet(location: location) }
        .sheet(isPresented: $addingLocation) { AddLocationSheet(parentLocation: location) }
        .sheet(item: $itemToShow)            { ItemDetailSheet(item: $0) }
        .sheet(item: $locationToEdit)        { LocationDetailSheet(location: $0) }
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
                    moveContentsToParent(of: loc)
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
                Button { locationToEdit = child }
                    label: { Label("Edit", systemImage: "pencil") }
                    .tint(.blue)
            }
        }
    }

    @ViewBuilder
    private func itemRows(_ items: [Item]) -> some View {
        ForEach(items) { item in
            Button { itemToShow = item } label: {
                ItemRow(item: item)
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    itemToDelete = item
                    showItemDeleteAlert = true
                } label: { Label("Delete", systemImage: "trash") }
                Button { itemToShow = item }
                    label: { Label("Edit", systemImage: "pencil") }
                    .tint(.blue)
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
                                    ancestor.id == location.id ? Color(.label) : .teal
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
        for child in loc.childList { cascadeDelete(child) }
        modelContext.delete(loc)
    }

    private func moveContentsToParent(of loc: Location) {
        let dest = loc.parent
        for child in loc.childList { child.parent   = dest }
        for item  in loc.itemList  { item.location  = dest }
        modelContext.delete(loc)
    }
}
