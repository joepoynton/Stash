//
//  ItemRow.swift
//  Stash
//

import SwiftUI

struct ItemRow: View {
    let item: Item

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            thumbnailView

            // Name + notes
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body)
                    .foregroundStyle(Color(.label))
                    .multilineTextAlignment(.leading)
                if let notes = item.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(Color(.secondaryLabel))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Inline quantity controls (shown only when tracking is on)
            if let qty = item.quantity {
                HStack(spacing: 6) {
                    Button {
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
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let data = item.photo, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.systemGray5))
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: "photo")
                        .font(.caption)
                        .foregroundStyle(Color(.tertiaryLabel))
                }
        }
    }
}
