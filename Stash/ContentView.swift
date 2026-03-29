//
//  ContentView.swift
//  Stash
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Home", systemImage: "house.fill") {
                Text("Home") // Phase 3
            }
            Tab("Browse", systemImage: "square.grid.2x2.fill") {
                BrowseTab()
            }
            Tab("Restock", systemImage: "cart.fill") {
                Text("Restock") // Phase 5
            }
        }
        .tint(.teal)
    }
}

#Preview {
    let schema = Schema([Location.self, Item.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    ContentView()
        .modelContainer(container)
}
