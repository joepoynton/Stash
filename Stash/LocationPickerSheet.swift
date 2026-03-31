//
//  LocationPickerSheet.swift
//  Stash
//
//  Tree picker used for "Move to…" in both location and item detail sheets.
//  Roots are shown on first open; branches expand/collapse independently via
//  a disclosure chevron. Tapping the name selects the destination.
//

import SwiftUI
import SwiftData

struct LocationPickerSheet: View {
    let title: String
    /// UUIDs to exclude from the picker (the location being moved + its descendants).
    let excludedIDs: Set<UUID>
    /// When true, shows a "Top Level" option that returns nil (makes location a root).
    let allowTopLevel: Bool
    let onSelect: (Location?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Location.name) private var allLocations: [Location]

    /// Tracks which nodes have been expanded by the user. Starts empty (all collapsed).
    @State private var expandedIDs: Set<UUID> = []

    // MARK: - Tree helpers

    private var roots: [Location] {
        allLocations
            .filter { $0.parent == nil && !excludedIDs.contains($0.id) }
            .sorted { $0.name < $1.name }
    }

    private func children(of location: Location) -> [Location] {
        allLocations
            .filter { $0.parent?.id == location.id && !excludedIDs.contains($0.id) }
            .sorted { $0.name < $1.name }
    }

    private func hasChildren(_ location: Location) -> Bool {
        allLocations.contains { $0.parent?.id == location.id && !excludedIDs.contains($0.id) }
    }

    /// Builds the list of visible rows by walking only expanded branches.
    private var visibleRows: [(location: Location, depth: Int)] {
        var result: [(Location, Int)] = []
        appendVisible(roots, depth: 0, into: &result)
        return result
    }

    private func appendVisible(_ locations: [Location], depth: Int, into result: inout [(Location, Int)]) {
        for loc in locations {
            result.append((loc, depth))
            if expandedIDs.contains(loc.id) {
                appendVisible(children(of: loc), depth: depth + 1, into: &result)
            }
        }
    }

    // MARK: - Body

    var body: some View {
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

                ForEach(visibleRows, id: \.location.id) { entry in
                    LocationPickerRow(
                        location: entry.location,
                        depth: entry.depth,
                        isExpanded: expandedIDs.contains(entry.location.id),
                        hasChildren: hasChildren(entry.location),
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
    let onToggle: () -> Void
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Indentation
            if depth > 0 {
                Spacer().frame(width: CGFloat(depth) * 20)
            }

            // Disclosure chevron — only occupies tap space when children exist
            Button(action: onToggle) {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color(.secondaryLabel))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .opacity(hasChildren ? 1 : 0)
                    .frame(width: 24, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!hasChildren)

            // Icon + name — tapping selects this location
            Button(action: onSelect) {
                HStack(spacing: 8) {
                    Image(systemName: location.icon ?? "folder.fill")
                        .frame(width: 24)
                        .foregroundStyle(location.icon != nil ? .teal : Color(.secondaryLabel))
                    Text(location.name)
                        .foregroundStyle(Color(.label))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
