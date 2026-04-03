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
