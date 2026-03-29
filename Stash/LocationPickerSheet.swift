//
//  LocationPickerSheet.swift
//  Stash
//
//  Tree picker used for "Move to…" in both location and item detail sheets.
//  Loads all locations once and flattens the tree with indentation levels.
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

    private var flatTree: [(location: Location, depth: Int)] {
        let roots = allLocations
            .filter { $0.parent == nil && !excludedIDs.contains($0.id) }
            .sorted { $0.name < $1.name }
        return flatten(roots, depth: 0)
    }

    private func flatten(_ locations: [Location], depth: Int) -> [(Location, Int)] {
        var result: [(Location, Int)] = []
        for loc in locations {
            result.append((loc, depth))
            let children = allLocations
                .filter { $0.parent?.id == loc.id && !excludedIDs.contains($0.id) }
                .sorted { $0.name < $1.name }
            result += flatten(children, depth: depth + 1)
        }
        return result
    }

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

                ForEach(flatTree, id: \.location.id) { entry in
                    Button {
                        onSelect(entry.location)
                        dismiss()
                    } label: {
                        HStack(spacing: 0) {
                            if entry.depth > 0 {
                                Color.clear.frame(width: CGFloat(entry.depth) * 20, height: 1)
                            }
                            Image(systemName: entry.location.icon ?? "folder.fill")
                                .frame(width: 24)
                                .foregroundStyle(entry.location.icon != nil ? .teal : Color(.secondaryLabel))
                            Text(entry.location.name)
                                .foregroundStyle(Color(.label))
                                .padding(.leading, 6)
                        }
                    }
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
