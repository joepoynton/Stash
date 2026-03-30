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
            if let qty = item.quantity {
                HStack(spacing: 6) {
                    Button {
                        item.decrementQuantity()
                    } label: {
                        Image(systemName: "minus")
                            .font(.caption.bold())
                            .frame(width: 26, height: 26)
                            .background(Color(.systemGray5))
                            .clipShape(Circle())
                            .foregroundStyle(qty == 0 ? Color(.tertiaryLabel) : Color(.label))
                    }
                    .buttonStyle(.plain)
                    .disabled(qty == 0)

                    VStack(spacing: 0) {
                        Text("\(qty)")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(Color(.label))
                        if let unit = item.unit, !unit.isEmpty {
                            Text(unit)
                                .font(.caption2)
                                .foregroundStyle(Color(.secondaryLabel))
                        }
                    }
                    .frame(minWidth: 28)

                    Button {
                        item.incrementQuantity()
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption.bold())
                            .frame(width: 26, height: 26)
                            .background(Color(.systemGray5))
                            .clipShape(Circle())
                            .foregroundStyle(Color(.label))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var locationPath: String {
        guard let location = item.location else { return "" }
        var parts: [String] = []
        var current: Location? = location
        while let loc = current {
            parts.insert(loc.name, at: 0)
            current = loc.parent
        }
        return parts.joined(separator: " › ")
    }
}
