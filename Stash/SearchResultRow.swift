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

    private var areaColor: Color {
        rootAreaColor(for: item.location) ?? .teal
    }

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
                            .foregroundStyle(areaColor)
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
        item.location?.pathString ?? ""
    }
}
