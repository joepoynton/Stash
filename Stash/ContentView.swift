//
//  ContentView.swift
//  Stash
//

import SwiftUI
import SwiftData

struct ContentView: View {
    /// Set by StashApp when the CloudKit store failed and we're running local-only.
    var showSyncUnavailableBanner: Bool = false

    @State private var navState    = NavigationState()
    @State private var recentStore = RecentlyAccessedStore()
    @State private var syncBannerDismissed = false

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
                RestockTab()
            }
        }
        .tint(.teal)
        .environment(navState)
        .environment(recentStore)
        .safeAreaInset(edge: .top) {
            if showSyncUnavailableBanner && !syncBannerDismissed {
                syncUnavailableBanner
            }
        }
    }

    private var syncUnavailableBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "icloud.slash")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("iCloud sync unavailable")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("Your items are safe on this device.")
                    .font(.caption)
                    .foregroundStyle(Color(.secondaryLabel))
            }
            Spacer()
            Button {
                withAnimation { syncBannerDismissed = true }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.bold())
                    .foregroundStyle(Color(.secondaryLabel))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }
}

#Preview {
    let schema = Schema([Location.self, Item.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    ContentView()
        .modelContainer(container)
}
