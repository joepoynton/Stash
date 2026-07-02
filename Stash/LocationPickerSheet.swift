//
//  LocationPickerSheet.swift
//  Stash
//
//  Tree picker used for "Move to…" in both location and item detail sheets.
//  Roots are shown on first open; branches expand/collapse independently via
//  a disclosure chevron. Tapping the name selects the destination.
//
//  Each row also offers "New Space here": create a child space under that
//  location, then use it as the destination in one flow. When top-level
//  selection is allowed, a matching option creates a new root Area.
//

import SwiftUI
import SwiftData

struct LocationPickerSheet: View {
    let title: String
    /// UUIDs to exclude from the picker (the location being moved + its descendants).
    let excludedIDs: Set<UUID>
    /// When true, shows a "Top Level" option that returns nil (makes location a root).
    let allowTopLevel: Bool
    /// Tracks which nodes have been expanded by the user.
    /// Passed in as a Binding so state survives across repeated openings of the sheet.
    @Binding var expandedIDs: Set<UUID>
    let onSelect: (Location?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Location.name) private var allLocations: [Location]

    // New-space creation. `newSpaceParent == nil` means create a new root Area.
    @State private var showNewSpaceAlert = false
    @State private var newSpaceName = ""
    @State private var newSpaceParent: Location? = nil

    // MARK: - Tree helpers

    /// Groups every (non-excluded) location by its parent id once per render —
    /// roots under the `nil` key. Replaces the previous per-node filtering of
    /// the full location list, which was O(n²) on deep/wide trees (P5).
    /// `allLocations` is already name-sorted by the @Query, so each group is too.
    private var childrenByParent: [UUID?: [Location]] {
        var dict: [UUID?: [Location]] = [:]
        for loc in allLocations where !excludedIDs.contains(loc.id) {
            dict[loc.parent?.id, default: []].append(loc)
        }
        return dict
    }

    /// Flattens the tree into visible rows, walking only expanded branches.
    /// Each row carries its own `hasChildren` so the body never re-queries.
    /// A visited-set bounds a corrupted parent/child cycle.
    private func visibleRows(_ tree: [UUID?: [Location]]) -> [(location: Location, depth: Int, hasChildren: Bool)] {
        var result: [(Location, Int, Bool)] = []
        var visited = Set<UUID>()

        func appendVisible(_ locations: [Location], depth: Int) {
            for loc in locations where visited.insert(loc.id).inserted {
                let kids = tree[loc.id] ?? []
                result.append((loc, depth, !kids.isEmpty))
                if expandedIDs.contains(loc.id) {
                    appendVisible(kids, depth: depth + 1)
                }
            }
        }

        appendVisible(tree[nil] ?? [], depth: 0)
        return result
    }

    // MARK: - Body

    var body: some View {
        let rows = visibleRows(childrenByParent)
        NavigationStack {
            List {
                if allowTopLevel {
                    Button {
                        onSelect(nil)
                        dismiss()
                    } label: {
                        Label("Top Level", systemImage: "square.grid.2x2.fill")
                            .foregroundStyle(Color(.label))
                    }
                    Button {
                        promptNewSpace(under: nil)
                    } label: {
                        Label("New Space at Top Level", systemImage: "folder.badge.plus")
                            .foregroundStyle(.teal)
                    }
                }

                ForEach(rows, id: \.location.id) { entry in
                    LocationPickerRow(
                        location: entry.location,
                        depth: entry.depth,
                        isExpanded: expandedIDs.contains(entry.location.id),
                        hasChildren: entry.hasChildren,
                        onToggle: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if expandedIDs.contains(entry.location.id) {
                                    expandedIDs.remove(entry.location.id)
                                } else {
                                    expandedIDs.insert(entry.location.id)
                                }
                            }
                        },
                        onSelect: {
                            onSelect(entry.location)
                            dismiss()
                        },
                        onAddChild: {
                            promptNewSpace(under: entry.location)
                        }
                    )
                    // Remove default List row tap — each button handles its own area.
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("New Space", isPresented: $showNewSpaceAlert) {
                TextField("Name", text: $newSpaceName)
                Button("Cancel", role: .cancel) { newSpaceName = "" }
                Button("Create") { createNewSpace() }
            } message: {
                Text(newSpaceParent == nil
                     ? "Create a new top-level space and move here."
                     : "Create a new space inside \"\(newSpaceParent?.name ?? "")\" and move here.")
            }
        }
    }

    // MARK: - New-space creation

    private func promptNewSpace(under parent: Location?) {
        newSpaceParent = parent
        newSpaceName = ""
        showNewSpaceAlert = true
    }

    /// Creates the child space, wires it into the tree, and hands it to
    /// `onSelect` as the move destination — the same path a tapped existing
    /// location takes. The parent is always a visible (non-excluded) row, so
    /// the new space can never land inside the subtree being moved.
    private func createNewSpace() {
        let trimmed = newSpaceName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        // Insert first, then set the parent so SwiftData maintains the inverse
        // relationship immediately (same pattern as item creation).
        let space = Location(name: trimmed)
        modelContext.insert(space)
        space.parent = newSpaceParent
        onSelect(space)
        newSpaceName = ""
        newSpaceParent = nil
        dismiss()
    }
}

// MARK: - Row view

private struct LocationPickerRow: View {
    let location: Location
    let depth: Int
    let isExpanded: Bool
    let hasChildren: Bool
    let onToggle: () -> Void
    let onSelect: () -> Void
    let onAddChild: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Indentation
            if depth > 0 {
                Spacer().frame(width: CGFloat(depth) * 20)
            }

            // Icon + name — tapping selects this location
            Button(action: onSelect) {
                HStack(spacing: 8) {
                    Image(systemName: location.icon ?? "folder.fill")
                        .frame(width: 24)
                        .foregroundStyle(location.icon != nil ? .teal : Color(.secondaryLabel))
                    Text(location.name)
                        .foregroundStyle(Color(.label))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Create a child space inside this one and move here — 44×44pt target.
            Button(action: onAddChild) {
                Image(systemName: "folder.badge.plus")
                    .font(.body)
                    .foregroundStyle(.teal)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New Space inside \(location.name)")

            // Disclosure chevron — trailing side, 44×44pt tap target, only when has children
            if hasChildren {
                Button(action: onToggle) {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color(.secondaryLabel))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
