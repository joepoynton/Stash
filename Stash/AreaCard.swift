//
//  AreaCard.swift
//  Stash
//
//  3:2 landscape card for a root Area. Shown in the Home tab grid.
//  - Photo background (if set) with gradient scrim for legibility
//  - Or solid tinted/neutral background with centred icon
//  - Name at bottom-left, low-stock dot at bottom-right
//  - When both photo and icon are set, a small icon badge appears bottom-left
//

import SwiftUI

struct AreaCard: View {
    let area: Location

    private var tintColor: Color {
        area.color.flatMap { Color(hex: $0) } ?? .teal
    }

    private var hasPhoto: Bool { area.photo != nil }
    private var hasColorTint: Bool { area.color != nil }

    private var nameTextColor: Color {
        if hasPhoto {
            return hasColorTint ? tintColor : .white
        } else if hasColorTint {
            return .white
        } else {
            return Color(.label)
        }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            backgroundLayer

            // Gradient scrim on photo cards — runs full height so bright sky/pale
            // photos remain legible at the bottom without a harsh flat dimming band.
            if hasPhoto {
                LinearGradient(
                    colors: [.black.opacity(0.6), .black.opacity(0.1)],
                    startPoint: .bottom,
                    endPoint: .top
                )
            }

            // Bottom bar: icon badge (optional) + name + low-stock dot
            HStack(alignment: .bottom, spacing: 6) {
                // Icon badge — shown only when the card has a photo AND an icon.
                // Reinforces area identity even when a photo is the primary visual.
                if hasPhoto, let icon = area.icon {
                    iconBadge(icon: icon)
                }

                Text(area.name)
                    .font(.headline)
                    .foregroundStyle(nameTextColor)
                    .lineLimit(2)
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
            .padding(.leading, 10)
        }
        .aspectRatio(3/2, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Icon badge (28pt circle, area colour background, icon in white)

    @ViewBuilder
    private func iconBadge(icon: String) -> some View {
        ZStack {
            Circle()
                .fill(tintColor)
                .frame(width: 28, height: 28)
            LocationIconView(icon: icon, font: .caption2, color: .white)
        }
        .padding(.bottom, 8)
    }

    // MARK: - Background layer

    @ViewBuilder
    private var backgroundLayer: some View {
        if let data = area.photo, let uiImage = UIImage(data: data) {
            // Photo background: GeometryReader ensures the image fills the
            // 3:2 frame exactly without squashing — scaledToFill + clipped
            // crops overflow rather than distorting the image.
            GeometryReader { geo in
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
        } else if let hexColor = area.color, let color = Color(hex: hexColor) {
            // Solid tinted background — icon in white
            color.overlay {
                LocationIconView(icon: area.icon ?? "archivebox.fill", font: .system(size: 36, weight: .medium), color: .white.opacity(0.85))
            }
        } else {
            // Neutral background — icon in secondary label colour
            Color(.secondarySystemBackground).overlay {
                LocationIconView(icon: area.icon ?? "archivebox.fill", font: .system(size: 36, weight: .medium), color: Color(.secondaryLabel))
            }
        }
    }
}
