//
//  Color+Hex.swift
//  Stash
//

import SwiftUI

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.hasPrefix("#") ? String(s.dropFirst()) : s
        guard s.count == 6, let value = UInt64(s, radix: 16) else { return nil }
        self.init(
            red:   Double((value & 0xFF0000) >> 16) / 255,
            green: Double((value & 0x00FF00) >> 8)  / 255,
            blue:  Double( value & 0x0000FF)         / 255
        )
    }

    /// Returns the hex string (e.g. "#2A9D8F") for this colour, or nil if the conversion fails.
    func toHex() -> String? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

// MARK: - Root area colour helper

/// Walks the ancestor chain from `location` to the root Area and returns
/// that Area's assigned colour. Returns nil when no colour is set, letting
/// call sites decide the fallback (usually `.teal`).
func rootAreaColor(for location: Location?) -> Color? {
    guard let location else { return nil }
    var current: Location? = location
    while let parent = current?.parent {
        current = parent
    }
    guard let hex = current?.color else { return nil }
    return Color(hex: hex)
}

// MARK: - Icon rendering helper

/// Renders a location icon string as either an SF Symbol or a plain Text emoji.
///
/// SF Symbol names are all-ASCII (e.g. "archivebox.fill"). Emoji and other
/// Unicode characters fail the ASCII check and are rendered as `Text` instead.
struct LocationIconView: View {
    let icon: String
    var font: Font = .title3
    var color: Color = .teal

    /// True when the icon string is a valid SF Symbol name (all-ASCII).
    var isSFSymbol: Bool { icon.allSatisfy { $0.isASCII } }

    var body: some View {
        if isSFSymbol {
            Image(systemName: icon)
                .font(font)
                .foregroundStyle(color)
        } else {
            Text(icon)
                .font(font)
        }
    }
}
