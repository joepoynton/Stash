//
//  ContentView.swift
//  Stash
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var navState    = NavigationState()
    @State private var recentStore = RecentlyAccessedStore()

    var body: some View {
        @Bindable var bindableNavState = navState
        TabView(selection: $bindableNavState.selectedTab) {
            Tab("Home", systemImage: "house.fill", value: 0) {
                HomeTab()
            }
            Tab("Browse", systemImage: "square.grid.2x2.fill", value: 1) {
                BrowseTab()
            }
            Tab("Restock", systemImage: "cart.fill", value: 2) {
                Text("Restock") // Phase 5
            }
        }
        .tint(.teal)
        .environment(navState)
        .environment(recentStore)
    }
}

#Preview {
    let schema = Schema([Location.self, Item.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    ContentView()
        .modelContainer(container)
}
