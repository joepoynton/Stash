//
//  ContentView.swift
//  Stash
//

import SwiftUI
import SwiftData
import CloudKit

struct ContentView: View {
    /// Set by StashApp when the CloudKit store failed and we're running local-only.
    var showSyncUnavailableBanner: Bool = false

    @State private var navState    = NavigationState()
    @State private var recentStore = RecentlyAccessedStore()
    @State private var syncBannerDismissed = false

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
