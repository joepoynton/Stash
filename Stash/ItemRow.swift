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
                HStack(spacing: 4) {
                    Text(item.name)
                        .font(.body)
                        .foregroundStyle(Color(.label))
                        .multilineTextAlignment(.leading)
                    if item.isOutOfPlace {
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                }
                if let notes = item.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(Color(.secondaryLabel))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Inline quantity controls (shown only when tracking is on)
            QuantityInputView(item: item)
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
