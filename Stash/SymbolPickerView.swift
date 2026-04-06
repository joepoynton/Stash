//
//  SymbolPickerView.swift
//  Stash
//
//  Icon picker for Location spaces. Supports:
//    - 50+ curated SF Symbols filterable by keyword search
//    - A single emoji character via the "Use Emoji" entry field
//
//  The `selected` binding stores either an SF Symbol name (e.g. "archivebox.fill")
//  or a single emoji character. Display logic elsewhere uses `LocationIconView`
//  to render the correct type.
//

import SwiftUI

struct SymbolPickerView: View {
    @Binding var selected: String?

    @State private var searchText = ""
    @State private var showEmojiEntry = false
    @State private var emojiText = ""
    @FocusState private var emojiFocused: Bool

    // MARK: - Symbol library (50+ curated symbols)

    private static let symbols: [String] = [
        // Storage & containers
        "archivebox.fill", "shippingbox.fill", "tray.fill", "tray.2.fill",
        "basket.fill", "bag.fill", "suitcase.fill", "backpack.fill",
        // Home & furniture
        "house.fill", "sofa.fill", "bed.double.fill", "building.2.fill",
        // Kitchen & food
        "fork.knife", "refrigerator.fill", "washer.fill", "cup.and.saucer.fill",
        // Vehicles & travel
        "car.fill", "car.circle.fill", "airplane", "bicycle",
        // Tools & workshop
        "hammer.fill", "wrench.and.screwdriver.fill", "screwdriver.fill",
        "paintbrush.fill", "scissors", "bolt.fill", "flashlight.on.fill",
        // Electronics & tech
        "tv.fill", "desktopcomputer", "laptopcomputer", "gamecontroller.fill",
        "camera.fill", "headphones", "printer.fill",
        // Work & documents
        "briefcase.fill", "books.vertical.fill", "folder.fill", "doc.fill",
        "tray.full.fill",
        // Health & personal care
        "heart.fill", "cross.case.fill", "pills.fill", "bandage.fill",
        // Garden & nature
        "leaf.fill", "sun.max.fill", "snowflake", "cloud.rain.fill",
        // Sports & hobbies
        "figure.walk", "trophy.fill", "sportscourt.fill",
        // Misc
        "star.fill", "tag.fill", "gift.fill", "bell.fill",
        "lightbulb.fill", "key.fill", "lock.fill", "cart.fill"
    ]

    private var filteredSymbols: [String] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return Self.symbols }
        return Self.symbols.filter { $0.contains(q) }
    }

    /// True when the current selection is an emoji (not an SF Symbol name).
    private var selectedIsEmoji: Bool {
        guard let s = selected, !s.isEmpty else { return false }
        return !s.allSatisfy { $0.isASCII }
    }

    private let columns = Array(repeating: GridItem(.flexible()), count: 6)

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            searchField

            if filteredSymbols.isEmpty {
                Text("No results for \"\(searchText)\"")
                    .font(.caption)
                    .foregroundStyle(Color(.secondaryLabel))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                symbolGrid
            }

            Divider()

            if showEmojiEntry {
                emojiEntryField
            }

            emojiToggleButton
        }
        .onAppear {
            if selectedIsEmoji {
                showEmojiEntry = true
                emojiText = selected ?? ""
            }
        }
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color(.secondaryLabel))
                .font(.subheadline)
            TextField("Search symbols…", text: $searchText)
                .font(.subheadline)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color(.tertiaryLabel))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Symbol grid

    private var symbolGrid: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(filteredSymbols, id: \.self) { symbol in
                let isSelected = selected == symbol
                Button {
                    if isSelected {
                        selected = nil
                    } else {
                        selected = symbol
                        // Switching to SF Symbol clears any emoji entry
                        emojiText = ""
                        showEmojiEntry = false
                    }
                } label: {
                    Image(systemName: symbol)
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .background(isSelected ? Color.teal.opacity(0.15) : Color(.systemGray6))
                        .foregroundStyle(isSelected ? .teal : Color(.label))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Emoji entry

    private var emojiEntryField: some View {
        HStack(spacing: 8) {
            TextField("Type or paste an emoji…", text: $emojiText)
                .focused($emojiFocused)
                .onChange(of: emojiText) { _, newValue in
                    // Accept only the first grapheme cluster
                    let trimmed = String(newValue.prefix(1))
                    if emojiText != trimmed { emojiText = trimmed }
                    selected = trimmed.isEmpty ? nil : trimmed
                }

            if !emojiText.isEmpty {
                Text(emojiText)
                    .font(.title2)
                Button {
                    emojiText = ""
                    selected = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color(.tertiaryLabel))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Emoji toggle

    private var emojiToggleButton: some View {
        Button {
            showEmojiEntry.toggle()
            if showEmojiEntry {
                // Pre-fill if an emoji is already selected
                emojiText = selectedIsEmoji ? (selected ?? "") : ""
                emojiFocused = true
            }
        } label: {
            Label(
                showEmojiEntry ? "Use Symbol Instead" : "Use Emoji",
                systemImage: showEmojiEntry ? "character.textbox" : "face.smiling"
            )
            .font(.subheadline)
            .foregroundStyle(.teal)
        }
        .buttonStyle(.plain)
    }
}
