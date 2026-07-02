//
//  IntentSnippets.swift
//  Stash
//
//  Small SwiftUI views rendered under an intent's spoken dialogue in Siri and
//  Shortcuts. Display-only (snippets are archived views, not live UI), so they
//  read straight from the entity snapshots the intents already produce.
//

import SwiftUI

// MARK: - Single item card (FindItem)

/// Photo + name + breadcrumb + status line for one item — the visual answer
/// to "where is my …".
struct ItemCardSnippetView: View {
    let item: ItemEntity

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let data = item.photoData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .aspectRatio(3 / 2, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.headline)
                Label(item.locationPath, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if item.quantity != nil {
                    Label(item.quantitySummary, systemImage: "number")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if item.isOutOfPlace {
                    Label(
                        item.outOfPlaceNote.map { "Out of place — \($0)" } ?? "Out of place",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.indigo)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Item list (What's In, Expiring, Restock)

/// A compact list of items: name + breadcrumb, with expiry or stock trailing.
struct ItemListSnippetView: View {
    let title: String
    let items: [ItemEntity]

    private static let maxRows = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            ForEach(items.prefix(Self.maxRows), id: \.id) { item in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(item.locationPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    trailingDetail(for: item)
                }
            }
            if items.count > Self.maxRows {
                Text("and \(items.count - Self.maxRows) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func trailingDetail(for item: ItemEntity) -> some View {
        if let expiry = item.expiryDate {
            Text(expiry.formatted(date: .abbreviated, time: .omitted))
                .font(.caption)
                .foregroundStyle(item.isExpired ? .red : .secondary)
        } else if item.quantity != nil {
            Text(item.quantitySummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
