//
//  RestockTab.swift
//  Stash
//

import SwiftUI
import SwiftData
import UIKit

// MARK: - RestockTab

struct RestockTab: View {
    @Query private var allItems: [Item]

    @State private var arrivedItem: Item?
    @State private var adjustMinItem: Item?

    var body: some View {
        NavigationStack {
            Group {
                if restockItems.isEmpty {
                    emptyState
                } else {
                    restockList
                }
            }
            .navigationTitle("Restock")
            .sheet(item: $arrivedItem) { item in
                ArrivalSheet(item: item)
            }
            .sheet(item: $adjustMinItem) { item in
                AdjustMinimumSheet(item: item)
            }
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack {
            Spacer()
            Text("Nothing to restock.")
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var restockList: some View {
        List {
            ForEach(groupedByArea) { group in
                Section {
                    ForEach(group.items) { item in
                        RestockRow(item: item)
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                if item.orderStatus == .onOrder {
                                    Button("Mark as Arrived") {
                                        arrivedItem = item
                                    }
                                    .tint(.teal)
                                } else {
                                    Button("Mark as Ordered") {
                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                        item.markAsOrdered()
                                    }
                                    .tint(.teal)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Adjust Minimum") {
                                    adjustMinItem = item
                                }
                                .tint(.blue)
                            }
                    }
                } header: {
                    AreaSectionHeader(area: group.area)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Data

    private var restockItems: [Item] {
        allItems.filter { item in
            if item.manuallyRestocking { return true }
            guard let qty = item.quantity, let min = item.minimumQuantity else { return false }
            return qty < min
        }
    }

    private var groupedByArea: [AreaGroup] {
        var order: [String] = []
        var dict: [String: AreaGroup] = [:]

        for item in restockItems {
            let root = rootAncestor(of: item.location)
            let key = root?.id.uuidString ?? "unknown"
            if dict[key] == nil {
                order.append(key)
                dict[key] = AreaGroup(area: root, items: [item])
            } else {
                dict[key]!.items.append(item)
            }
        }

        return order
            .compactMap { dict[$0] }
            .sorted {
                switch ($0.area, $1.area) {
                case (let a?, let b?): return a.name < b.name
                case (nil, _): return false
                case (_, nil): return true
                }
            }
            .map { AreaGroup(area: $0.area, items: $0.items.sorted { $0.name < $1.name }) }
    }
}

// MARK: - AreaGroup

private struct AreaGroup: Identifiable {
    let id: String = UUID().uuidString
    let area: Location?
    var items: [Item]

    init(area: Location?, items: [Item]) {
        self.area = area
        self.items = items
    }
}

// MARK: - AreaSectionHeader

private struct AreaSectionHeader: View {
    let area: Location?

    private var areaColor: Color {
        area?.color.flatMap { Color(hex: $0) } ?? .teal
    }

    var body: some View {
        HStack(spacing: 6) {
            if let icon = area?.icon {
                LocationIconView(icon: icon, font: .caption, color: areaColor)
            }
            Text(area?.name ?? "Unknown")
                .foregroundStyle(areaColor)
        }
    }
}

// MARK: - RestockRow

private struct RestockRow: View {
    let item: Item

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body)
                Text(locationPath(for: item.location))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                quantityText
                statusBadge
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var quantityText: some View {
        if let qty = item.quantity, let min = item.minimumQuantity {
            let display = item.unit.map { "\(qty) / \(min) \($0)" } ?? "\(qty) / \(min)"
            Text(display)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if item.manuallyRestocking && item.orderStatus != .onOrder {
            Text("Wanted")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.teal)
        } else {
            switch item.orderStatus {
            case .onOrder:
                HStack(spacing: 3) {
                    Image(systemName: "shippingbox")
                        .font(.caption2)
                    Text("On Order")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundStyle(.teal)
            default:
                Text("Low")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.orange)
            }
        }
    }
}

// MARK: - ArrivalSheet

private struct ArrivalSheet: View {
    let item: Item
    @Environment(\.dismiss) private var dismiss
    @State private var arrivedCount: Int = 1

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("Arrived: \(arrivedCount)", value: $arrivedCount, in: 1...999)
                } header: {
                    Text("How many arrived?")
                } footer: {
                    if let qty = item.quantity, let min = item.minimumQuantity {
                        let newQty = qty + arrivedCount
                        if newQty < min {
                            Text("Will still be below minimum (\(newQty) of \(min) \(item.unit ?? "")).")
                        } else {
                            Text("Will reach or exceed minimum (\(newQty) of \(min) \(item.unit ?? "")).")
                        }
                    }
                }
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        item.markAsArrived(count: arrivedCount)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - AdjustMinimumSheet

private struct AdjustMinimumSheet: View {
    let item: Item
    @Environment(\.dismiss) private var dismiss
    @State private var minimum: Int = 1

    @State private var editingMinimum = false
    @State private var minimumEntryText = ""
    @FocusState private var minimumFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Button {
                            guard minimum > 1 else { return }
                            minimum -= 1
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.title2)
                                .foregroundStyle(minimum <= 1 ? Color(.tertiaryLabel) : .teal)
                        }
                        .buttonStyle(.plain)
                        .disabled(minimum <= 1)

                        Spacer()

                        minimumDisplay

                        Spacer()

                        Button {
                            minimum += 1
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.teal)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                } footer: {
                    if let qty = item.quantity {
                        if qty < minimum {
                            Text("Item will remain in Restock (\(qty) on hand).")
                        } else {
                            Text("Item will leave Restock (\(qty) on hand).")
                        }
                    }
                }
            }
            .navigationTitle("Adjust Minimum")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        item.minimumQuantity = minimum
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    if editingMinimum {
                        Button("Done") { commitMinimumEntry() }
                    }
                }
            }
            .onChange(of: minimumFieldFocused) { _, isFocused in
                if !isFocused && editingMinimum { commitMinimumEntry() }
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            minimum = item.minimumQuantity ?? 1
        }
    }

    @ViewBuilder
    private var minimumDisplay: some View {
        if editingMinimum {
            TextField("1", text: $minimumEntryText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.title.monospacedDigit())
                .focused($minimumFieldFocused)
                .frame(minWidth: 60)
        } else {
            Text("\(minimum)")
                .font(.title.monospacedDigit())
                .foregroundStyle(Color(.label))
                .underline(color: Color(.tertiaryLabel))
                .contentShape(Rectangle())
                .onTapGesture {
                    minimumEntryText = "\(minimum)"
                    editingMinimum = true
                    minimumFieldFocused = true
                }
        }
    }

    private func commitMinimumEntry() {
        guard editingMinimum else { return }
        if let value = Int(minimumEntryText), value >= 1 {
            minimum = value
        }
        editingMinimum = false
        minimumEntryText = ""
        minimumFieldFocused = false
    }
}

// MARK: - Helpers

/// Walks up the parent chain to find the root Area.
private func rootAncestor(of location: Location?) -> Location? {
    guard let location else { return nil }
    var current = location
    var depth = 0
    while let parent = current.parent, depth < 50 {
        current = parent
        depth += 1
    }
    return current
}

/// Builds the full path string from root to the given location, e.g. "Garage › Top Shelf".
private func locationPath(for location: Location?) -> String {
    guard let location else { return "" }
    var parts: [String] = []
    var current: Location? = location
    var depth = 0
    while let loc = current, depth < 50 {
        parts.insert(loc.name, at: 0)
        current = loc.parent
        depth += 1
    }
    return parts.joined(separator: " › ")
}
