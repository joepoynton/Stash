//
//  SymbolPickerView.swift
//  Stash
//

import SwiftUI

struct SymbolPickerView: View {
    @Binding var selected: String?

    private let symbols = [
        "archivebox.fill", "shippingbox.fill", "car.fill", "car.circle.fill",
        "house.fill", "building.2.fill", "fork.knife", "refrigerator.fill",
        "bed.double.fill", "sofa.fill", "washer.fill", "tv.fill",
        "briefcase.fill", "desktopcomputer", "books.vertical.fill", "folder.fill",
        "gamecontroller.fill", "camera.fill", "heart.fill", "cross.case.fill",
        "leaf.fill", "hammer.fill", "wrench.and.screwdriver.fill", "screwdriver.fill",
        "bolt.fill", "lightbulb.fill", "key.fill", "lock.fill",
        "cart.fill", "bag.fill", "basket.fill", "tray.fill",
        "paintbrush.fill", "star.fill", "tag.fill", "gift.fill"
    ]

    private let columns = Array(repeating: GridItem(.flexible()), count: 6)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(symbols, id: \.self) { symbol in
                Button {
                    selected = (selected == symbol) ? nil : symbol
                } label: {
                    Image(systemName: symbol)
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .background(selected == symbol ? Color.teal.opacity(0.15) : Color(.systemGray6))
                        .foregroundStyle(selected == symbol ? .teal : Color(.label))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
