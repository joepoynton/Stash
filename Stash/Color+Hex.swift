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
}
