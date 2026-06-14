//
//  DesignSystem.swift
//  Stash
//
//  Shared design-system primitives used across the app so screens that were
//  built incrementally read as one designed surface rather than an assembly
//  of one-off styles. Everything here is presentation-only — no model logic.
//
//  Contents:
//  - StatusColor:        single source of truth for item-state colours/labels
//  - AreaPalette:        the area colour swatches (was duplicated per sheet)
//  - SectionHeader:      exactly two header levels, used everywhere
//  - StatusBadge:        the pill/label used for low-stock / on-order / etc.
//  - NumericEntryField:  one tap-to-type +/- control for all numeric entry
//  - Haptics:            one light-impact policy for every write action
//

import SwiftUI
import UIKit

// MARK: - StatusColor

/// Maps an item's state to its colour and canonical label. This is the single
/// source of truth — every badge, swipe tint, and attention row routes through
/// here so a colour never means two different things on two different screens.
///
/// Meaning of the palette (C1):
/// - low stock   → orange (a warning: do something)
/// - on order    → teal   (calm: already handled)
/// - out of place → indigo
/// - expired     → red
///
/// `expiringSoon` and `notVerified` are softer attention states not called out
/// in the spec; they reuse orange (a gentle warning) and secondary-label grey.
enum StatusColor {
    case lowStock
    case onOrder
    case outOfPlace
    case expired
    case expiringSoon
    case notVerified

    var color: Color {
        switch self {
        case .lowStock:     .orange
        case .onOrder:      .teal
        case .outOfPlace:   Color(.systemIndigo)
        case .expired:      .red
        case .expiringSoon: .orange
        case .notVerified:  Color(.secondaryLabel)
        }
    }

    var label: String {
        switch self {
        case .lowStock:     "Low stock"
        case .onOrder:      "On order"
        case .outOfPlace:   "Out of place"
        case .expired:      "Expired"
        case .expiringSoon: "Expires soon"
        case .notVerified:  "Not verified"
        }
    }
}

// MARK: - Area palette

/// The eight named area colours. Previously duplicated verbatim in
/// AddLocationSheet and LocationDetailSheet — now defined once.
enum AreaPalette {
    static let colors: [(name: String, hex: String)] = [
        ("Teal",   "#2A9D8F"), ("Blue",   "#3A86FF"), ("Purple", "#8338EC"),
        ("Pink",   "#FF006E"), ("Orange", "#FB5607"), ("Yellow", "#FFBE0B"),
        ("Green",  "#06D6A0"), ("Red",    "#E63946")
    ]
}

// MARK: - SectionHeader

/// The app's section header. Exactly two levels (C3) so every list across
/// Home, search, and Restock reads with the same rhythm:
/// - `.primary`   — large bold section titles ("Needs Attention", "Your Spaces")
/// - `.secondary` — quieter grouping labels ("Recently Accessed", "Items")
///
/// An optional leading `icon` and `tint` let the Restock area headers carry
/// their area colour without inventing a third style — the level still
/// controls typography.
struct SectionHeader: View {
    enum Level {
        case primary
        case secondary
    }

    let title: String
    var level: Level = .primary
    var icon: String? = nil
    var tint: Color? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                LocationIconView(icon: icon, font: iconFont, color: tint ?? defaultColor)
            }
            Text(title)
                .font(font)
                .foregroundStyle(tint ?? defaultColor)
        }
        .textCase(nil)
    }

    private var font: Font {
        switch level {
        case .primary:   .title2.bold()
        case .secondary: .subheadline.weight(.semibold)
        }
    }

    private var iconFont: Font {
        switch level {
        case .primary:   .title3
        case .secondary: .caption
        }
    }

    private var defaultColor: Color {
        switch level {
        case .primary:   Color(.label)
        case .secondary: Color(.secondaryLabel)
        }
    }
}

// MARK: - StatusBadge

/// The small state indicator shown on rows and in the detail sheet.
/// `.filled` renders a tinted capsule (used in the Needs Attention list);
/// the default plain style is a coloured icon + text label.
struct StatusBadge: View {
    let text: String
    let color: Color
    var systemImage: String? = nil
    var filled: Bool = false

    var body: some View {
        if filled {
            label
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(color.opacity(0.12), in: Capsule())
        } else {
            label
        }
    }

    private var label: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2)
            }
            Text(text)
        }
        .font(.caption)
        .fontWeight(.medium)
        .foregroundStyle(color)
    }
}

// MARK: - NumericEntryField

/// One numeric control for the whole app (C4): a minus button, a tappable
/// number that becomes a number-pad field, and a plus button. Replaces the
/// four hand-rolled +/- blocks and the bare Stepper in ArrivalSheet, so a
/// value like "24 arrived" can be typed directly everywhere.
///
/// `.prominent` spreads the controls across the full row width (the primary
/// quantity controls); the compact style is a tight cluster placed after a
/// label (the "Minimum" rows). Every change fires a light haptic (C5).
struct NumericEntryField: View {
    @Binding var value: Int
    var range: ClosedRange<Int> = 0...9_999
    var unit: String? = nil
    var prominent: Bool = true

    @State private var editing = false
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if prominent {
                HStack {
                    minusButton
                    Spacer()
                    numberView
                    Spacer()
                    plusButton
                }
            } else {
                HStack(spacing: 14) {
                    minusButton
                    numberView
                    plusButton
                }
            }
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused && editing { commit() }
        }
    }

    private var canDecrement: Bool { value > range.lowerBound }
    private var canIncrement: Bool { value < range.upperBound }

    private var minusButton: some View {
        Button {
            guard canDecrement else { return }
            Haptics.write()
            setValue(value - 1)
        } label: {
            Image(systemName: "minus.circle.fill")
                .font(.title2)
                .foregroundStyle(canDecrement ? .teal : Color(.tertiaryLabel))
        }
        .buttonStyle(.plain)
        .disabled(!canDecrement)
    }

    private var plusButton: some View {
        Button {
            guard canIncrement else { return }
            Haptics.write()
            setValue(value + 1)
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.title2)
                .foregroundStyle(canIncrement ? .teal : Color(.tertiaryLabel))
        }
        .buttonStyle(.plain)
        .disabled(!canIncrement)
    }

    @ViewBuilder
    private var numberView: some View {
        if editing {
            TextField("\(range.lowerBound)", text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.title.monospacedDigit())
                .focused($focused)
                .frame(minWidth: 60)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { commit() }
                    }
                }
        } else {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(value)")
                    .font(.title.monospacedDigit())
                    .foregroundStyle(Color(.label))
                    .underline(color: Color(.tertiaryLabel))   // subtle tap hint
                if let unit, !unit.isEmpty {
                    Text(unit)
                        .font(.title3)
                        .foregroundStyle(Color(.secondaryLabel))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                text = "\(value)"
                editing = true
                focused = true
            }
        }
    }

    private func setValue(_ newValue: Int) {
        value = min(max(newValue, range.lowerBound), range.upperBound)
    }

    private func commit() {
        if let entered = Int(text) {
            setValue(entered)
        }
        editing = false
        text = ""
        focused = false
    }
}

// MARK: - Haptics

/// One haptic policy for the whole app (C5): every write action — quantity
/// change, verify, mark ordered/arrived, out of place, delete — calls
/// `Haptics.write()` for a single light impact. A shared generator is kept
/// prepared so repeated taps stay low-latency.
enum Haptics {
    @MainActor private static let generator: UIImpactFeedbackGenerator = {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        return generator
    }()

    @MainActor
    static func write() {
        generator.impactOccurred()
        generator.prepare()   // keep the taptic engine warm for the next tap
    }
}
