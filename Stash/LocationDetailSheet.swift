//
//  LocationDetailSheet.swift
//  Stash
//

import SwiftUI
import SwiftData

struct LocationDetailSheet: View {
    @Bindable var location: Location

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var showMoveSheet = false
    @State private var showDeleteActionSheet = false
    @State private var showCascadeConfirm = false
    @State private var showEmptyDeleteConfirm = false

    static let areaColors: [(name: String, hex: String)] = [
        ("Teal",   "#2A9D8F"), ("Blue",   "#3A86FF"), ("Purple", "#8338EC"),
        ("Pink",   "#FF006E"), ("Orange", "#FB5607"), ("Yellow", "#FFBE0B"),
        ("Green",  "#06D6A0"), ("Red",    "#E63946")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $location.name)
                }

                if location.isRoot {
                    Section("Icon") {
                        SymbolPickerView(selected: $location.icon)
                            .padding(.vertical, 4)
                    }
                    Section("Colour") {
                        colorSwatches
                            .padding(.vertical, 4)
                    }
                }

                Section {
                    Button {
                        showMoveSheet = true
                    } label: {
                        Label("Move to…", systemImage: "arrow.up.arrow.down")
                            .foregroundStyle(.teal)
                    }
                }

                Section {
                    Button("Delete Space", role: .destructive) {
                        if location.childList.isEmpty && location.itemList.isEmpty {
                            showEmptyDeleteConfirm = true
                        } else {
                            showDeleteActionSheet = true
                        }
                    }
                }
            }
            .navigationTitle("Edit Space")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showMoveSheet) {
                LocationPickerSheet(
                    title: "Move to…",
                    excludedIDs: selfAndDescendantIDs,
                    allowTopLevel: true,
                    onSelect: { newParent in
                        location.parent = newParent
                    }
                )
            }
            .confirmationDialog(
                "Delete \"\(location.name)\"?",
                isPresented: $showDeleteActionSheet,
                titleVisibility: .visible
            ) {
                Button("Delete everything inside", role: .destructive) {
                    showCascadeConfirm = true
                }
                Button("Move contents to \(location.parent?.name ?? "Top Level")") {
                    moveContentsToParent()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Are you sure?", isPresented: $showCascadeConfirm) {
                Button("Delete everything", role: .destructive) {
                    cascadeDelete(location)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone.")
            }
            .alert("Delete \"\(location.name)\"?", isPresented: $showEmptyDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    modelContext.delete(location)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone.")
            }
        }
    }

    // MARK: - Colour swatches

    private var colorSwatches: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 10) {
            Button {
                location.color = nil
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.systemGray3), lineWidth: 1.5)
                        .frame(width: 44, height: 44)
                    if location.color == nil {
                        Image(systemName: "checkmark")
                            .font(.caption.bold())
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                }
            }
            .buttonStyle(.plain)

            ForEach(Self.areaColors, id: \.hex) { swatch in
                Button {
                    location.color = swatch.hex
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(hex: swatch.hex) ?? .teal)
                            .frame(width: 44, height: 44)
                        if location.color == swatch.hex {
                            Image(systemName: "checkmark")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Helpers

    private var selfAndDescendantIDs: Set<UUID> {
        var ids = Set<UUID>()
        collectIDs(of: location, into: &ids)
        return ids
    }

    private func collectIDs(of loc: Location, into ids: inout Set<UUID>) {
        ids.insert(loc.id)
        for child in loc.childList { collectIDs(of: child, into: &ids) }
    }

    private func cascadeDelete(_ loc: Location) {
        for child in loc.childList { cascadeDelete(child) }
        modelContext.delete(loc)
    }

    private func moveContentsToParent() {
        let dest = location.parent
        for child in location.childList { child.parent = dest }
        for item  in location.itemList  { item.location = dest }
        modelContext.delete(location)
    }
}
