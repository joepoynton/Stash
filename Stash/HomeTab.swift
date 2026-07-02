//
//  HomeTab.swift
//  Stash
//
//  Dashboard tab. Shows Needs Attention, Recently Accessed, and the Area card grid.
//  Search lives in SearchResultsView (shared with Browse): live search across
//  item names, location names, and notes.
//

import SwiftUI
import SwiftData

// MARK: - Attention reason

private enum AttentionReason {
    case outOfPlace
    case lowStock
    case expired
    case expiringSoon
    case notVerified

    /// Maps to the shared StatusColor so colour + label have one source of
    /// truth across every screen (C1).
    private var statusColor: StatusColor {
        switch self {
        case .outOfPlace:   .outOfPlace
        case .lowStock:     .lowStock
        case .expired:      .expired
        case .expiringSoon: .expiringSoon
        case .notVerified:  .notVerified
        }
    }

    var label: String { statusColor.label }

    var color: Color { statusColor.color }

    /// Severity order for the Needs Attention list. Lower sorts first.
    var rank: Int {
        switch self {
        case .outOfPlace:   0
        case .lowStock:     1
        case .expired:      2
        case .expiringSoon: 3
        case .notVerified:  4
        }
    }
}

// MARK: - HomeTab

struct HomeTab: View {
    @Query(sort: \Location.dateCreated) private var allLocations: [Location]
    @Query private var allItems: [Item]

    @Environment(NavigationState.self) private var navState
    @Environment(RecentlyAccessedStore.self) private var recentStore
    @Environment(\.modelContext) private var modelContext
    @Environment(StoreKitManager.self) private var storeKit

    @AppStorage("staleThresholdDays") private var staleThresholdDays = 90

    @State private var showSettings = false
    @State private var showAddArea = false
    @State private var selectedItem: Item? = nil
    @State private var searchText = ""
    @State private var showUpgradePrompt = false
    @State private var showAllAttention = false
    @State private var showQuickAdd = false
    @State private var quickAddArea: Location? = nil
    @State private var areaToEdit: Location? = nil

    /// Needs Attention shows at most this many rows until "Show all" is tapped.
    private static let attentionCap = 5

    // MARK: Derived data

    private var rootAreas: [Location] {
        allLocations.filter { $0.parent == nil }
    }

    private var needsAttentionItems: [(item: Item, reason: AttentionReason)] {
        let now = Date()
        let expiryThreshold = now.addingTimeInterval(30 * 86400)
        let staleThreshold  = now.addingTimeInterval(-Double(staleThresholdDays) * 86400)

        return allItems.compactMap { item -> (item: Item, reason: AttentionReason)? in
            if item.isOutOfPlace {
                return (item, .outOfPlace)
            }
            if item.orderStatus == .low {
                return (item, .lowStock)
            }
            if let expiry = item.expiryDate {
                // Shared Item helpers (also used by ExpiringItemsIntent) keep
                // Siri's "expiring soon" in lockstep with this section.
                if expiry <= now {
                    return (item, .expired)
                }
                if expiry <= expiryThreshold {
                    return (item, .expiringSoon)
                }
            }
            if item.lastVerified <= staleThreshold && !item.neverStale {
                return (item, .notVerified)
            }
            return nil
        }
        .sorted {
            if $0.reason.rank != $1.reason.rank { return $0.reason.rank < $1.reason.rank }
            return $0.item.name < $1.item.name
        }
    }

    private var recentItems: [Item] {
        // uniquingKeysWith: duplicate UUIDs (possible after a CloudKit merge)
        // must not trap the whole tab.
        let byID = Dictionary(allItems.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { a, _ in a })
        return recentStore.orderedIDs.compactMap { byID[$0] }
    }

    /// Free tier at (or over) the item cap — adding must show the paywall, not the form.
    private var atFreeLimit: Bool {
        !storeKit.isPro && allItems.count >= FeatureFlags.freeItemLimit
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            Group {
                if !searchText.isEmpty {
                    SearchResultsView(
                        searchText: searchText,
                        onSelectItem: { selectedItem = $0 },
                        onNavigate: { searchText = "" }
                    )
                } else if rootAreas.isEmpty {
                    emptyState
                } else {
                    mainContent
                }
            }
            .navigationTitle("Stash")
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search items, spaces, notes…"
            )
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button { presentQuickAdd(in: nil) } label: {
                            Label("New Item", systemImage: "plus.square")
                        }
                        .disabled(rootAreas.isEmpty)
                        Button { showAddArea = true } label: {
                            Label("New Space", systemImage: "folder.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gear")
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showAddArea) {
            AddLocationSheet(parentLocation: nil)
        }
        .sheet(item: $selectedItem) {
            ItemDetailSheet(item: $0)
        }
        .sheet(isPresented: $showQuickAdd) {
            QuickAddSheet()
        }
        .sheet(item: $quickAddArea) {
            QuickAddSheet(location: $0)
        }
        .sheet(item: $areaToEdit) {
            LocationDetailSheet(location: $0)
        }
        .sheet(isPresented: $showUpgradePrompt) {
            UpgradePromptSheet(
                message: "You have \(allItems.count) items. Unlock Stash Pro for unlimited items, photos, and data export."
            )
        }
    }

    /// Quick add gated by the free-tier cap: at the limit the paywall shows
    /// instead of the entry form. nil area = pickable location (Home "+").
    private func presentQuickAdd(in area: Location?) {
        if atFreeLimit {
            showUpgradePrompt = true
        } else if let area {
            quickAddArea = area
        } else {
            showQuickAdd = true
        }
    }

    // MARK: Main content

    private var mainContent: some View {
        List {
            overLimitBanner
            unplacedItemsSection
            needsAttentionSection
            yourSpacesSection
            recentlyAccessedSection
        }
        .listStyle(.insetGrouped)
    }

    // MARK: Items without a place (recovery)

    /// Items whose location was lost (location == nil). These are invisible
    /// in the Browse tree, so surface them here for the user to re-home.
    private var unplacedItems: [Item] {
        allItems.filter { $0.location == nil }.sorted { $0.name < $1.name }
    }

    @ViewBuilder
    private var unplacedItemsSection: some View {
        let items = unplacedItems
        if !items.isEmpty {
            Section {
                ForEach(items) { item in
                    Button { selectedItem = item } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "questionmark.folder")
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .foregroundStyle(Color(.label))
                                Text("Tap to give it a home")
                                    .font(.caption)
                                    .foregroundStyle(Color(.secondaryLabel))
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color(.tertiaryLabel))
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                SectionHeader(title: "Items without a place", level: .secondary)
            }
        }
    }

    // MARK: Over-limit banner (free users who have exceeded 25 items)

    @ViewBuilder
    private var overLimitBanner: some View {
        if !storeKit.isPro && allItems.count > FeatureFlags.freeItemLimit {
            Section {
                Button {
                    showUpgradePrompt = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.teal)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("You have \(allItems.count) items")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(Color(.label))
                            Text("Upgrade to Stash Pro to add more")
                                .font(.caption)
                                .foregroundStyle(Color(.secondaryLabel))
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color(.tertiaryLabel))
                    }
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Needs Attention

    @ViewBuilder
    private var needsAttentionSection: some View {
        let items = needsAttentionItems
        let displayed = showAllAttention ? items : Array(items.prefix(Self.attentionCap))
        if !items.isEmpty {
            Section {
                ForEach(displayed, id: \.item.id) { entry in
                    NeedsAttentionRow(
                        item: entry.item,
                        reason: entry.reason,
                        onTap: { selectedItem = entry.item },
                        onNeverStale: entry.reason == .notVerified
                            ? { Haptics.write(); entry.item.neverStale = true }
                            : nil
                    )
                    .listRowInsets(EdgeInsets())
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        attentionSwipeActions(for: entry)
                    }
                }

                // Cap row — a long attention list must not push Your Spaces
                // below the fold.
                if items.count > Self.attentionCap {
                    Button {
                        withAnimation { showAllAttention.toggle() }
                    } label: {
                        Text(showAllAttention ? "Show fewer" : "Show all (\(items.count))")
                            .font(.subheadline)
                            .foregroundStyle(.teal)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                SectionHeader(title: "Needs Attention", level: .primary)
            }
        }
    }

    @ViewBuilder
    private func attentionSwipeActions(for entry: (item: Item, reason: AttentionReason)) -> some View {
        switch entry.reason {
        case .lowStock:
            Button {
                Haptics.write()
                entry.item.markAsOrdered()
            } label: {
                Label("Mark as Ordered", systemImage: "shippingbox.fill")
            }
            // Ordering moves the item to the calm "on order" state (C1 teal),
            // not the orange low-stock warning it's leaving behind.
            .tint(StatusColor.onOrder.color)
        case .outOfPlace:
            Button {
                Haptics.write()
                entry.item.returnToPlace()
            } label: {
                Label("Return to Place", systemImage: "arrow.down.circle.fill")
            }
            .tint(.teal)
        case .expired, .expiringSoon:
            Button {
                Haptics.write()
                entry.item.markAsReplaced()
            } label: {
                Label("Replaced it", systemImage: "arrow.triangle.2.circlepath")
            }
            .tint(.teal)
        case .notVerified:
            Button {
                Haptics.write()
                entry.item.markAsVerified()
            } label: {
                Label("Mark as Verified", systemImage: "checkmark.circle.fill")
            }
            .tint(.teal)
            Button {
                Haptics.write()
                entry.item.neverStale = true
            } label: {
                Label("Always Verified", systemImage: "checkmark.shield.fill")
            }
            .tint(.teal)
        }
    }

    // MARK: Your Spaces

    @ViewBuilder
    private var yourSpacesSection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 12) {
                ForEach(rootAreas) { area in
                    Button {
                        navState.browseNavigationPath = [area]
                        navState.selectedTab = 1
                    } label: {
                        AreaCard(area: area)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button { presentQuickAdd(in: area) } label: {
                            Label("Add Item", systemImage: "plus.square")
                        }
                        Button { areaToEdit = area } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        if !area.childList.isEmpty {
                            Button {
                                navState.pendingReorderLocationID = area.id
                                navState.browseNavigationPath = [area]
                                navState.selectedTab = 1
                            } label: {
                                Label("Reorder Spaces", systemImage: "arrow.up.arrow.down")
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 4)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } header: {
            SectionHeader(title: "Your Spaces", level: .primary)
        }
    }

    // MARK: Recently Accessed

    @ViewBuilder
    private var recentlyAccessedSection: some View {
        let items = recentItems
        if !items.isEmpty {
            Section {
                ForEach(items) { item in
                    RecentlyAccessedRow(item: item, onTap: { selectedItem = item })
                        .listRowInsets(EdgeInsets())
                }
            } header: {
                SectionHeader(title: "Recently Accessed", level: .secondary)
            }
        }
    }

    // MARK: Empty state (onboarding)

    private static let onboardingChips: [(name: String, icon: String)] = [
        ("Garage",  "car.fill"),
        ("Loft",    "shippingbox.fill"),
        ("Car",     "car.circle.fill"),
        ("Kitchen", "fork.knife"),
        ("Bedroom", "bed.double.fill"),
        ("Office",  "desktopcomputer"),
        ("Work",    "briefcase.fill"),
        ("Shed",    "wrench.and.screwdriver.fill")
    ]

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 48)

                VStack(spacing: 8) {
                    Text("Start by adding your spaces")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    Text("Where do you keep things? Garage, loft, car — add them here.")
                        .font(.subheadline)
                        .foregroundStyle(Color(.secondaryLabel))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Self.onboardingChips, id: \.name) { chip in
                            Button {
                                createArea(name: chip.name, icon: chip.icon)
                            } label: {
                                Label(chip.name, systemImage: chip.icon)
                                    .font(.subheadline)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(Capsule())
                                    .foregroundStyle(Color(.label))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }

                Button {
                    showAddArea = true
                } label: {
                    Label("Add a custom space", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .tint(.teal)

                Spacer(minLength: 48)
            }
        }
    }

    private func createArea(name: String, icon: String) {
        let location = Location(name: name, icon: icon)
        modelContext.insert(location)
    }
}

// MARK: - Needs Attention row

private struct NeedsAttentionRow: View {
    let item: Item
    let reason: AttentionReason
    let onTap: () -> Void
    let onNeverStale: (() -> Void)?

    /// Colour of the root area this item belongs to — used for the left accent bar.
    private var accentColor: Color {
        rootAreaColor(for: item.location) ?? .teal
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left accent bar tinted in the item's root area colour
            Rectangle()
                .fill(accentColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.body)
                            .foregroundStyle(Color(.label))
                        if !locationPath.isEmpty {
                            Text(locationPath)
                                .font(.caption)
                                .foregroundStyle(Color(.secondaryLabel))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { onTap() }

                    VStack(alignment: .trailing, spacing: 6) {
                        StatusBadge(text: reason.label, color: reason.color, filled: true)

                        // Inline ± so low stock can be fixed without opening the sheet
                        QuantityInputView(item: item)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, onNeverStale != nil ? 6 : 10)

                if let action = onNeverStale {
                    Button(action: action) {
                        Text("Always verified")
                            .font(.caption)
                            .foregroundStyle(.teal)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                }
            }
        }
    }

    private var locationPath: String {
        item.location?.pathString ?? ""
    }
}

// MARK: - Recently Accessed row

private struct RecentlyAccessedRow: View {
    let item: Item
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.subheadline)
                    .foregroundStyle(Color(.label))
                if !locationPath.isEmpty {
                    Text(locationPath)
                        .font(.caption2)
                        .foregroundStyle(Color(.secondaryLabel))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { onTap() }

            // Inline ± replaces the old read-only quantity text
            QuantityInputView(item: item)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
    }

    private var locationPath: String {
        item.location?.pathString ?? ""
    }
}
