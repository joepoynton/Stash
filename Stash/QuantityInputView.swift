//
//  QuantityInputView.swift
//  Stash
//
//  Compact inline quantity control for Browse rows and search results.
//  Shows − / number / + with small gray circle buttons.
//
//  Haptic: routed through the shared Haptics helper so every write across the
//  app uses one light-impact policy (C5).
//

import SwiftUI
import UIKit

struct QuantityInputView: View {
    let item: Item

    var body: some View {
        if let qty = item.quantity {
            HStack(spacing: 6) {
                Button {
                    Haptics.write()
                    item.decrementQuantity()
                } label: {
                    Image(systemName: "minus")
                        .font(.caption.bold())
                        .frame(width: 26, height: 26)
                        .background(Color(.systemGray5))
                        .clipShape(Circle())
                        .foregroundStyle(qty == 0 ? Color(.tertiaryLabel) : Color(.label))
                }
                .buttonStyle(.plain)
                .disabled(qty == 0)

                VStack(spacing: 0) {
                    Text("\(qty)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(Color(.label))
                    if let unit = item.unit, !unit.isEmpty {
                        Text(unit)
                            .font(.caption2)
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                }
                .frame(minWidth: 28)

                Button {
                    Haptics.write()
                    item.incrementQuantity()
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.bold())
                        .frame(width: 26, height: 26)
                        .background(Color(.systemGray5))
                        .clipShape(Circle())
                        .foregroundStyle(Color(.label))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
