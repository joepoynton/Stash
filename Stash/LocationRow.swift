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

    private var areaColor: Color? {
        location.color.flatMap { Color(hex: $0) }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail: photo (Phase 6) or icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(areaColor?.opacity(0.15) ?? Color(.systemGray5))
                    .frame(width: 44, height: 44)

                if let photoData = location.photo, let uiImage = UIImage(data: photoData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if let icon = location.icon {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(areaColor ?? .teal)
                } else {
                    Image(systemName: "folder.fill")
                        .font(.title3)
                        .foregroundStyle(Color(.secondaryLabel))
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
}
