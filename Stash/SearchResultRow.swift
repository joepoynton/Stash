//
//  SearchResultRow.swift
//  Stash
//
//  Search result row: item name, tappable location path, inline ± quantity.
//  No photo thumbnail per spec. Lives inside the SearchResultsView List.
//

import SwiftUI

struct SearchResultRow: View {
    let item: Item
    let onTap: () -> Void
    /// Tapping the location path deep-links into Browse at the item's location.
    let onLocationTap: () -> Void

    private var areaColor: Color {
        rootAreaColor(for: item.location) ?? .teal
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                // Name — tap opens detail sheet
                Text(item.name)
                    .font(.headline)
                    .foregroundStyle(Color(.label))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { onTap() }

                // Location path — tap jumps to the location in Browse
                if !locationPath.isEmpty {
                    Button(action: onLocationTap) {
                        HStack(spacing: 3) {
                            Text(locationPath)
                                .multilineTextAlignment(.leading)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .fontWeight(.semibold)
                        }
                        .font(.caption)
                        .foregroundStyle(areaColor)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Inline quantity controls (only when quantity tracking is on)
            QuantityInputView(item: item)
        }
        .padding(.vertical, 2)
    }

    private var locationPath: String {
        item.location?.pathString ?? ""
    }
}
