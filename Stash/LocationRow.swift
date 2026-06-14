//
//  LocationRow.swift
//  Stash
//

import SwiftUI

struct LocationRow: View {
    let location: Location

    private var subtitleText: String {
        let childCount = location.childList.count
        let itemCount  = location.itemList.count
        let parts: [String] = [
            childCount > 0 ? "\(childCount) \(childCount == 1 ? "space" : "spaces")" : nil,
            itemCount  > 0 ? "\(itemCount) \(itemCount  == 1 ? "item"  : "items")"  : nil
        ].compactMap { $0 }
        return parts.joined(separator: " · ")
    }

    /// Walks up to the root ancestor to get the area colour.
    /// Returns nil when no root colour is assigned (caller falls back to .teal or gray).
    private var areaColor: Color? {
        rootAreaColor(for: location)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail: cached photo, or icon (SF Symbol or emoji) as placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(areaColor?.opacity(0.15) ?? Color(.systemGray5))
                    .frame(width: 44, height: 44)

                CachedThumbnail(
                    id: location.id,
                    size: CGSize(width: 44, height: 44),
                    dataProvider: { location.photo }
                ) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } placeholder: {
                    iconPlaceholder
                }
            }

            // Name + counts
            VStack(alignment: .leading, spacing: 2) {
                Text(location.name)
                    .font(.body)
                    .foregroundStyle(Color(.label))
                if !subtitleText.isEmpty {
                    Text(subtitleText)
                        .font(.caption)
                        .foregroundStyle(Color(.secondaryLabel))
                }
            }

            Spacer()

            // Low-stock dot
            if location.hasLowStockDescendant {
                Circle()
                    .fill(areaColor ?? .teal)
                    .frame(width: 8, height: 8)
            }

            // Chevron
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(Color(.tertiaryLabel))
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var iconPlaceholder: some View {
        if let icon = location.icon {
            LocationIconView(icon: icon, font: .title3, color: areaColor ?? .teal)
        } else {
            // Default folder icon tinted in the area colour
            Image(systemName: "folder.fill")
                .font(.title3)
                .foregroundStyle(areaColor ?? .teal)
        }
    }
}
