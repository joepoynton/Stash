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

    private var hasColorTint: Bool { area.color != nil }

    var body: some View {
        // Read the photo's presence once per render rather than via several
        // computed properties that each re-fault the externally-stored blob.
        let hasPhoto = area.photo != nil

        // C7: on photo cards the title is always white for legibility — the
        // area's colour identity is carried by the icon badge and nav tint,
        // not the title, which could clash with a bright photo.
        let nameTextColor: Color = hasPhoto ? .white : (hasColorTint ? .white : Color(.label))

        ZStack(alignment: .bottomLeading) {
            backgroundLayer(hasPhoto: hasPhoto)

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
    private func backgroundLayer(hasPhoto: Bool) -> some View {
        if hasPhoto {
            // Photo background via the shared thumbnail cache at card resolution —
            // the full ~1200px JPEG is decoded once, off-main, downscaled to the
            // card, then served from memory on every subsequent render (P1).
            CachedThumbnail(
                id: area.id,
                size: CGSize(width: 280, height: 187),
                dataProvider: { area.photo }
            ) { image in
                GeometryReader { geo in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
            } placeholder: {
                // Shown only for the brief first decode; the scrim + white title
                // sit on top, so it reads as a dimmed card, not an empty one.
                Color(.secondarySystemBackground)
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
