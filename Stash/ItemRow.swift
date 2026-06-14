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

    private var thumbnailView: some View {
        CachedThumbnail(
            id: item.id,
            size: CGSize(width: 44, height: 44),
            dataProvider: { item.photo }
        ) { image in
            image
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } placeholder: {
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
