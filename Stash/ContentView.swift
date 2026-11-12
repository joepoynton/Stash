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

    // "Open in Stash": a CSV or backup handed over from Files, Mail or the
    // share sheet (1.3). Results are held until the import sheet has closed so
    // the alerts don't fight its dismissal.
    @Environment(\.modelContext) private var modelContext
    @Environment(StoreKitManager.self) private var storeKit
    @State private var openedImport: OpenedImport?
    @State private var restoreDataFromFlow: Data?
    @State private var restoreData: Data?
    @State private var importResultMessage: String?
    @State private var showImportResult = false
    @State private var upgradeMessage = ""
    @State private var showUpgradePrompt = false

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
        .onOpenURL { handleOpenedURL($0) }
        .sheet(item: $openedImport, onDismiss: finishOpenedImport) { opened in
            SpreadsheetImportView(
                onRestore: { restoreDataFromFlow = $0 },
                onFinished: { importResultMessage = $0 },
                openedFile: opened.file
            )
        }
        .sheet(isPresented: $showUpgradePrompt) {
            UpgradePromptSheet(message: upgradeMessage)
        }
        .backupRestorePrompt(data: $restoreData)
        .alert("Import Complete", isPresented: $showImportResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importResultMessage ?? "")
        }
    }

    // MARK: - Open in Stash

    /// File types Stash accepts from other apps (matches Info.plist).
    private static let openableExtensions: Set<String> = ["csv", "tsv", "tab", "txt", "text", "json"]

    private func handleOpenedURL(_ url: URL) {
        guard url.isFileURL, Self.openableExtensions.contains(url.pathExtension.lowercased()) else { return }

        // Read it now, then remove the copy iOS put in Stash's Inbox.
        let file = ImportFileReader.read(url)
        if url.deletingLastPathComponent().lastPathComponent == "Inbox" {
            try? FileManager.default.removeItem(at: url)
        }

        // Same free-tier gate as Settings: at the item limit, offer Pro instead.
        let itemCount = (try? modelContext.fetchCount(FetchDescriptor<Item>())) ?? 0
        if !storeKit.isPro && itemCount >= FeatureFlags.freeItemLimit {
            upgradeMessage = "You've used \(itemCount) of \(FeatureFlags.freeItemLimit) free items. Unlock Stash Pro for unlimited items, photos, and data export."
            showUpgradePrompt = true
            return
        }
        importResultMessage = nil
        restoreDataFromFlow = nil
        openedImport = OpenedImport(file: file)
    }

    /// Runs once the import sheet has closed: shows its result, or starts the
    /// restore if the file was a Stash backup.
    private func finishOpenedImport() {
        if importResultMessage != nil {
            showImportResult = true
        } else if let data = restoreDataFromFlow {
            restoreDataFromFlow = nil
            restoreData = data
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

/// A file waiting in the import sheet. Identifiable so the sheet can be
/// driven by it.
private struct OpenedImport: Identifiable {
    let id = UUID()
    let file: ImportOpenedFile
}

#Preview {
    let schema = Schema([Location.self, Item.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    ContentView()
        .modelContainer(container)
}
