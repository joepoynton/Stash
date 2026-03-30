//
//  AreaCard.swift
//  Stash
//
//  3:2 landscape card for a root Area. Shown in the Home tab grid.
//  - Photo background (if set) with 40% black overlay
//  - Or solid tinted/neutral background with centred icon
//  - Name at bottom-left, low-stock dot at bottom-right
//

import SwiftUI

struct AreaCard: View {
    let area: Location

    private var tintColor: Color {
        area.color.flatMap { Color(hex: $0) } ?? .teal
    }

    private var hasPhoto: Bool { area.photo != nil }
    private var hasColorTint: Bool { area.color != nil }

    var body: some View {
        ZStack(alignment: .bottom) {
            backgroundLayer

            // Gradient scrim on photo cards for text legibility
            if hasPhoto {
                LinearGradient(
                    colors: [.black.opacity(0.55), .clear],
                    startPoint: .bottom,
                    endPoint: .center
                )
            }

            // Bottom bar: name + low-stock dot
            HStack(alignment: .bottom, spacing: 0) {
                Text(area.name)
                    .font(.headline)
                    .foregroundStyle(hasPhoto || hasColorTint ? .white : Color(.label))
                    .lineLimit(2)
                    .padding(.leading, 10)
                    .padding(.bottom, 8)

                Spacer(minLength: 4)

                if area.hasLowStockDescendant {
                    Circle()
                        .fill(tintColor)
                        .frame(width: 8, height: 8)
                        .padding(.trailing, 10)
                        .padding(.bottom, 10)
                }
            }
        }
        .aspectRatio(3/2, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        if let data = area.photo, let uiImage = UIImage(data: data) {
            // Photo background with dark overlay
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .overlay(Color.black.opacity(0.4))
        } else if let hexColor = area.color, let color = Color(hex: hexColor) {
            // Solid tinted background — icon in white
            color.overlay {
                Image(systemName: area.icon ?? "archivebox.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
        } else {
            // Neutral background — icon in secondary label colour
            Color(.secondarySystemBackground).overlay {
                Image(systemName: area.icon ?? "archivebox.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(Color(.secondaryLabel))
            }
        }
    }
}
