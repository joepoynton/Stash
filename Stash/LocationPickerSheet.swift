//
//  LocationPickerSheet.swift
//  Stash
//
//  Tree picker used for "Move to…" in both location and item detail sheets.
//  Roots are shown on first open; branches expand/collapse independently via
//  tapping the row. Only the separate Select button chooses a destination.
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
    /// Optional deferred-placement choice, used only by Quick Add.
    var onChooseUnsorted: (() -> Void)? = nil

    @State private var searchText = ""

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Location.name) private var allLocations: [Location]

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
                }

                if let onChooseUnsorted {
                    Button {
                        onChooseUnsorted()
                        dismiss()
                    } label: {
                        Label("Unsorted", systemImage: "tray.fill")
                            .foregroundStyle(Color(.label))
                    }
                }

                if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let matches = allLocations.filter {
                        !excludedIDs.contains($0.id) &&
                        $0.pathString.localizedStandardContains(searchText.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    if matches.isEmpty {
                        Text("No matching spaces")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(matches) { location in
                        LocationPickerRow(
                            location: location,
                            depth: 0,
                            isExpanded: false,
                            hasChildren: false,
                            subtitle: location.pathString,
                            onToggle: {},
                            onSelect: {
                                onSelect(location)
                                dismiss()
                            }
                        )
                    }
                } else {
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
                            }
                        )
                        // Remove default List row tap — each button handles its own area.
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Find a space")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Row view

private struct LocationPickerRow: View {
    let location: Location
    let depth: Int
    let isExpanded: Bool
    let hasChildren: Bool
    var subtitle: String? = nil
    let onToggle: () -> Void
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Indentation
            if depth > 0 {
                Spacer().frame(width: CGFloat(depth) * 20)
            }

            // Branch rows navigate; leaves and search labels never select on tap.
            if hasChildren {
                Button(action: onToggle) {
                    locationLabel
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(isExpanded ? "Collapse" : "Expand") \(location.name)")
            } else {
                locationLabel
            }

            Button("Select", action: onSelect)
                .buttonStyle(.bordered)
                .tint(.teal)
                .frame(minHeight: 44)
                .accessibilityLabel("Select \(location.pathString)")
        }
    }

    private var locationLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: location.icon ?? "folder.fill")
                .frame(width: 24)
                .foregroundStyle(location.icon != nil ? .teal : Color(.secondaryLabel))
            VStack(alignment: .leading, spacing: 4) {
                Text(location.name)
                    .foregroundStyle(Color(.label))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if hasChildren {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color(.secondaryLabel))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 44)
        .padding(.trailing, 12)
    }
}
