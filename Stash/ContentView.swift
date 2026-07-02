//
//  ContentView.swift
//  Stash
//

import SwiftUI
import SwiftData
import CloudKit
import CoreSpotlight

struct ContentView: View {
    /// Set by StashApp when the CloudKit store failed and we're running local-only.
    var showSyncUnavailableBanner: Bool = false

    @State private var navState    = NavigationState()
    @State private var recentStore = RecentlyAccessedStore()
    @State private var syncBannerDismissed = false

    /// Item presented by an intent (OpenItemIntent, Spotlight tap-through).
    /// Presented as a root-level sheet so it works from any tab.
    @State private var intentItem: Item? = nil

    /// F10: true when no iCloud account is signed in. The dismissal is one-time
    /// (persisted) so the gentle "not backed up" warning never nags.
    @State private var iCloudNoAccount = false
    @AppStorage("iCloudNoAccountBannerDismissed") private var noAccountBannerDismissed = false

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
                syncBanner(
                    title: "iCloud sync unavailable",
                    subtitle: "Your items are safe on this device.",
                    onDismiss: { syncBannerDismissed = true }
                )
            } else if iCloudNoAccount && !noAccountBannerDismissed {
                syncBanner(
                    title: "Not backed up to iCloud",
                    subtitle: "Sign in to iCloud in Settings to back up and sync your inventory.",
                    onDismiss: { noAccountBannerDismissed = true }
                )
            }
        }
        .task { await checkICloudAccount() }
        // MARK: Intent routing (OpenItem / OpenLocation / Spotlight)
        // onChange covers intents arriving while the app is up; onAppear
        // covers an intent that cold-launched the app before views existed.
        .onChange(of: IntentRouter.shared.pendingItemID) { consumePendingIntentRoutes() }
        .onChange(of: IntentRouter.shared.pendingLocationID) { consumePendingIntentRoutes() }
        .onChange(of: IntentRouter.shared.pendingSearchText) { consumePendingIntentRoutes() }
        .onAppear { consumePendingIntentRoutes() }
        // Spotlight tap-through on an indexed item/space. OpenItemIntent is
        // the modern path; this user activity is the long-standing fallback.
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            if let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
                IntentRouter.shared.handleSpotlightIdentifier(identifier)
            }
        }
        .sheet(item: $intentItem) { item in
            ItemDetailSheet(item: item)
                .environment(navState)
                .environment(recentStore)
        }
    }

    /// Consumes pending intent destinations. Item opens win over location
    /// opens if both are somehow set; search is handed off to BrowseTab
    /// (which owns the search field) — we just switch to the right tab.
    private func consumePendingIntentRoutes() {
        let router = IntentRouter.shared

        if let id = router.pendingItemID {
            router.pendingItemID = nil
            if let item = IntentStore.item(id: id) {
                intentItem = item
            }
        }

        if let id = router.pendingLocationID {
            router.pendingLocationID = nil
            if let location = IntentStore.location(id: id) {
                navState.browseNavigationPath = location.ancestorChain
                navState.selectedTab = 1
            }
        }

        if router.pendingSearchText != nil {
            // Leave the text in place for BrowseTab to consume on appear.
            navState.selectedTab = 1
        }
    }

    /// Checks the iCloud account once. Skipped when the CloudKit store already
    /// failed to open — that case is covered by the other banner.
    private func checkICloudAccount() async {
        guard !showSyncUnavailableBanner, !noAccountBannerDismissed else { return }
        let status = try? await CKContainer.default().accountStatus()
        iCloudNoAccount = (status == .noAccount)
    }

    private func syncBanner(title: String, subtitle: String, onDismiss: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "icloud.slash")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color(.secondaryLabel))
            }
            Spacer()
            Button {
                withAnimation { onDismiss() }
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
