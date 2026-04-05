//
//  SearchResultRow.swift
//  Stash
//
//  Search result row: item name, location path, quantity + inline ±/- buttons.
//  No photo thumbnail per spec.
//

import SwiftUI

struct SearchResultRow: View {
    let item: Item
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Name + location path — tap opens detail sheet
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.headline)
                        .foregroundStyle(Color(.label))
                        .multilineTextAlignment(.leading)
                    if !locationPath.isEmpty {
                        Text(locationPath)
                            .font(.caption)
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            // Inline quantity controls (only when quantity tracking is on)
            QuantityInputView(item: item)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var locationPath: String {
        guard let location = item.location else { return "" }
        var parts: [String] = []
        var current: Location? = location
        var depth = 0
        while let loc = current, depth < 50 {
            parts.insert(loc.name, at: 0)
            current = loc.parent
            depth += 1
        }
        return parts.joined(separator: " › ")
    }
}
