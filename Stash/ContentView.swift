//
//  ContentView.swift
//  Stash
//
//  Phase 1 test scaffold — verifies CRUD, relationships, move, cascade delete,
//  derived orderStatus, and hasLowStockDescendant. Replace in Phase 2.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var locations: [Location]

    var rootLocations: [Location] {
        locations.filter { $0.parent == nil }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(rootLocations) { area in
                    Section {
                        // Area header row
                        HStack {
                            if let icon = area.icon {
                                Image(systemName: icon)
                                    .foregroundStyle(.teal)
                            }
                            Text(area.name).font(.headline)
                            Spacer()
                            if area.hasLowStockDescendant {
                                Circle()
                                    .fill(.teal)
                                    .frame(width: 8, height: 8)
                            }
                        }

                        // Direct items
                        ForEach(area.itemList) { item in
                            itemRow(item)
                        }

                        // Child locations and their items
                        ForEach(area.childList) { child in
                            HStack {
                                Text("  › \(child.name)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if child.hasLowStockDescendant {
                                    Circle()
                                        .fill(.teal)
                                        .frame(width: 6, height: 6)
                                }
                            }
                            ForEach(child.itemList) { item in
                                itemRow(item).padding(.leading, 12)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Stash — Phase 1")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Seed") { seedTestData() }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Clear", role: .destructive) { clearAll() }
                }
            }
        }
    }

    @ViewBuilder
    private func itemRow(_ item: Item) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                Text(item.location?.name ?? "—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let qty = item.quantity {
                Text("\(qty)\(item.unit.map { " \($0)" } ?? "")")
                    .monospacedDigit()
            }
            switch item.orderStatus {
            case .low:
                Text("LOW")
                    .font(.caption).bold()
                    .foregroundStyle(.teal)
            case .onOrder:
                Text("ON ORDER")
                    .font(.caption).bold()
                    .foregroundStyle(.orange)
            case .normal:
                EmptyView()
            }
        }
    }

    // MARK: - Test operations

    /// Seeds a two-level tree with items in various stock states to exercise the model.
    private func seedTestData() {
        // Area: Garage
        let garage = Location(name: "Garage", icon: "car.fill", color: "#2A9D8F")
        modelContext.insert(garage)

        // Child: Top Shelf inside Garage
        let shelf = Location(name: "Top Shelf", parent: garage)
        modelContext.insert(shelf)

        // Item at garage level — below minimum (will surface as .low)
        let wd40 = Item(name: "WD-40", location: garage)
        wd40.quantity = 1
        wd40.unit = "cans"
        wd40.minimumQuantity = 3
        modelContext.insert(wd40)

        // Item on shelf — adequate stock
        let tape = Item(name: "Duct Tape", location: shelf)
        tape.quantity = 5
        tape.unit = "rolls"
        tape.minimumQuantity = 2
        modelContext.insert(tape)

        // Item on shelf — on order
        let batteries = Item(name: "AA Batteries", location: shelf)
        batteries.quantity = 0
        batteries.minimumQuantity = 8
        batteries.unit = "pack"
        batteries.markAsOrdered()
        modelContext.insert(batteries)

        // Test: move wd40 from garage to shelf
        wd40.location = shelf

        // Test: hasLowStockDescendant should be true on garage (wd40 is low, batteries is on order)
        // Expected: garage shows teal dot (wd40 is low and not on order)
    }

    /// Clears all data for retesting.
    private func clearAll() {
        for location in locations {
            modelContext.delete(location)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Location.self, Item.self], inMemory: true)
}
