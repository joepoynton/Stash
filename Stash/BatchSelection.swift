//
//  BatchSelection.swift
//  Stash
//
//  Select mode on a Browse screen (roadmap Phase 4): pick several items and
//  move, verify, restock or delete them in one go. The state lives in
//  BrowseLocationView; this file holds the row, the bottom bar and the
//  sheet and alerts, to keep that view small enough to type-check.
//

import SwiftUI

// MARK: - Row

/// An item row while selecting. A tap anywhere toggles it; the quantity
/// buttons inside ItemRow are covered so a tap can't change a count by accident.
struct SelectableItemRow: View {
    let item: Item
    let isSelected: Bool
    let tint: Color
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? tint : Color(.tertiaryLabel))
            ItemRow(item: item)
        }
        .overlay {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: toggle)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.name)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { toggle() }
    }
}

// MARK: - Bottom bar

struct BatchActionBar: View {
    let selectedItems: [Item]
    let onMove: () -> Void
    let onVerify: () -> Void
    let onRestock: () -> Void
    let onDelete: () -> Void

    var body: some View {
        let nothingSelected = selectedItems.isEmpty
        // Restock only means something for items that track a quantity.
        let canRestock = selectedItems.contains { $0.quantity != nil && !$0.manuallyRestocking }

        HStack(spacing: 0) {
            barButton("Move", systemImage: "arrow.up.arrow.down", action: onMove)
                .disabled(nothingSelected)
            barButton("Verify", systemImage: "checkmark.seal", action: onVerify)
                .disabled(nothingSelected)
            barButton("Restock", systemImage: "cart.badge.plus", action: onRestock)
                .disabled(!canRestock)
            barButton("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                .disabled(nothingSelected)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func barButton(_ title: String, systemImage: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.title3)
                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderless)
        .tint(role == .destructive ? .red : nil)
    }
}

// MARK: - Sheet and alerts

struct BatchSelectionSheets: ViewModifier {
    let location: Location
    let selectedCount: Int
    @Binding var showMove: Bool
    @Binding var showDelete: Bool
    @Binding var showVerifyAll: Bool
    @Binding var pickerExpandedIDs: Set<UUID>
    let onMove: (Location) -> Void
    let onDelete: () -> Void
    let onVerifyAll: () -> Void

    private var itemsText: String { selectedCount == 1 ? "1 Item" : "\(selectedCount) Items" }

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showMove) {
                LocationPickerSheet(
                    title: "Move \(itemsText)",
                    excludedIDs: [],
                    allowTopLevel: false,
                    expandedIDs: $pickerExpandedIDs,
                    onSelect: { newLocation in
                        if let newLocation { onMove(newLocation) }
                    }
                )
            }
            .alert("Delete \(itemsText.lowercased())?", isPresented: $showDelete) {
                Button("Delete \(itemsText)", role: .destructive, action: onDelete)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone.")
            }
            .alert("Verify All Here?", isPresented: $showVerifyAll) {
                Button("Verify All", action: onVerifyAll)
                Button("Cancel", role: .cancel) {}
            } message: {
                let count = location.itemList.count
                Text("Mark all \(count) \(count == 1 ? "item" : "items") in \(location.name) as verified?")
            }
    }
}
