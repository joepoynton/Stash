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
                                        Haptics.write()
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
            let root = item.location?.rootAncestor
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
    let area: Location?
    var items: [Item]

    // Stable identity per area so SwiftUI keeps view identity (and
    // animations) across renders.
    var id: String { area?.id.uuidString ?? "unknown" }
}

// MARK: - AreaSectionHeader

private struct AreaSectionHeader: View {
    let area: Location?

    private var areaColor: Color {
        area?.color.flatMap { Color(hex: $0) } ?? .teal
    }

    var body: some View {
        // Shared header (level .secondary) carrying the area's colour + icon.
        SectionHeader(
            title: area?.name ?? "Unknown",
            level: .secondary,
            icon: area?.icon,
            tint: areaColor
        )
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
                Text(item.location?.pathString ?? "")
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
            // Manual flag — neutral annotation, not a stock alarm (C2 wording).
            StatusBadge(text: "Added manually", color: Color(.secondaryLabel))
        } else {
            switch item.orderStatus {
            case .onOrder:
                StatusBadge(
                    text: StatusColor.onOrder.label,
                    color: StatusColor.onOrder.color,
                    systemImage: "shippingbox"
                )
            default:
                StatusBadge(text: "Low", color: StatusColor.lowStock.color)
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
                    // Direct numeric entry — orders are often 12 or 24, which a
                    // bare Stepper made tediously slow to reach (C4).
                    NumericEntryField(value: $arrivedCount, range: 1...999)
                        .padding(.vertical, 4)
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
                        Haptics.write()
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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NumericEntryField(value: $minimum, range: 1...9_999)
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
                        Haptics.write()
                        item.minimumQuantity = minimum
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            minimum = item.minimumQuantity ?? 1
        }
    }
}
