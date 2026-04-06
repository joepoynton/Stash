//
//  HomeTab.swift
//  Stash
//
//  Dashboard tab. Shows Needs Attention, Recently Accessed, and the Area card grid.
//  Search bar (Phase 4): live search across item names, location names, and notes.
//

import SwiftUI
import SwiftData

// MARK: - Attention reason

private enum AttentionReason {
    case lowStock
    case expiringSoon
    case notVerified
    case outOfPlace

    var label: String {
        switch self {
        case .lowStock:     "Low stock"
        case .expiringSoon: "Expires soon"
        case .notVerified:  "Not verified"
        case .outOfPlace:   "Out of place"
        }
    }

    var color: Color {
        switch self {
        case .lowStock:     .teal
        case .expiringSoon: .orange
        case .notVerified:  Color(.secondaryLabel)
        case .outOfPlace:   Color(.systemIndigo)
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

    @AppStorage("staleThresholdDays") private var staleThresholdDays = 90

    @State private var showSettings = false
    @State private var showAddArea = false
    @State private var selectedItem: Item? = nil
    @State private var searchText = ""

    // MARK: Derived data

    private var rootAreas: [Location] {
        allLocations.filter { $0.parent == nil }
    }

    private var needsAttentionItems: [(item: Item, reason: AttentionReason)] {
        let now = Date()
        let expiryThreshold = now.addingTimeInterval(30 * 86400)
        let staleThreshold  = now.addingTimeInterval(-Double(staleThresholdDays) * 86400)

        return allItems.compactMap { item in
            if item.isOutOfPlace {
                return (item, .outOfPlace)
            }
            if item.orderStatus == .low {
                return (item, .lowStock)
            }
            if let expiry = item.expiryDate, expiry <= expiryThreshold {
                return (item, .expiringSoon)
            }
            if item.lastVerified <= staleThreshold && !item.neverStale {
                return (item, .notVerified)
            }
            return nil
        }
    }

    private var recentItems: [Item] {
        let byID = Dictionary(uniqueKeysWithValues: allItems.map { ($0.id.uuidString, $0) })
        return recentStore.orderedIDs.compactMap { byID[$0] }
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            Group {
                if !searchText.isEmpty {
                    searchResultsContent
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
                    Button { showAddArea = true } label: {
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
    }

    // MARK: Search

    /// Items whose own name or notes field matches — location name is intentionally excluded
    /// so location matches surface only in the Spaces section.
    private var filteredItems: [Item] {
        let q = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return allItems.filter { item in
            item.name.lowercased().contains(q) ||
            (item.notes?.lowercased().contains(q) == true)
        }
    }

    /// Locations whose name matches the query.
    private var filteredLocations: [Location] {
        let q = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return allLocations
            .filter { $0.name.lowercased().contains(q) }
            .sorted { $0.name < $1.name }
    }

    @ViewBuilder
    private var searchResultsContent: some View {
        let items     = filteredItems
        let locations = filteredLocations

        if items.isEmpty && locations.isEmpty {
            VStack {
                Spacer()
                Text("No results for \"\(searchText)\"")
                    .foregroundStyle(Color(.secondaryLabel))
                    .multilineTextAlignment(.center)
                    .padding()
                Spacer()
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {

                    // MARK: Items section
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Items")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color(.secondaryLabel))
                                .padding(.horizontal, 4)

                            VStack(spacing: 0) {
                                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                    SearchResultRow(item: item, onTap: { selectedItem = item })
                                    if index < items.count - 1 {
                                        Divider().padding(.leading, 16)
                                    }
                                }
                            }
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }

                    // MARK: Spaces section
                    if !locations.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Spaces")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color(.secondaryLabel))
                                .padding(.horizontal, 4)

                            VStack(spacing: 0) {
                                ForEach(Array(locations.enumerated()), id: \.element.id) { index, location in
                                    SearchLocationRow(location: location) {
                                        navigateToLocation(location)
                                    }
                                    if index < locations.count - 1 {
                                        Divider().padding(.leading, 52)
                                    }
                                }
                            }
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
        }
    }

    /// Deep-links into the Browse tab at the given location, building the full ancestor chain.
    private func navigateToLocation(_ location: Location) {
        var chain: [Location] = []
        var current: Location? = location
        while let loc = current {
            chain.insert(loc, at: 0)
            current = loc.parent
        }
        navState.browseNavigationPath = chain
        navState.selectedTab = 1
    }

    // MARK: Main content

    private var mainContent: some View {
        List {
            needsAttentionSection
            yourSpacesSection
            recentlyAccessedSection
        }
        .listStyle(.insetGrouped)
    }

    // MARK: Needs Attention

    @ViewBuilder
    private var needsAttentionSection: some View {
        let items = needsAttentionItems
        if !items.isEmpty {
            Section {
                ForEach(items, id: \.item.id) { entry in
                    NeedsAttentionRow(
                        item: entry.item,
                        reason: entry.reason,
                        onTap: { selectedItem = entry.item },
                        onNeverStale: entry.reason == .notVerified
                            ? { entry.item.neverStale = true }
                            : nil
                    )
                    .listRowInsets(EdgeInsets())
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if entry.reason == .lowStock {
                            Button {
                                entry.item.markAsOrdered()
                            } label: {
                                Label("Mark as Ordered", systemImage: "shippingbox.fill")
                            }
                            .tint(.orange)
                        }
                    }
                }
            } header: {
                Text("Needs Attention")
                    .font(.title2).bold()
                    .foregroundStyle(Color(.label))
                    .textCase(nil)
            }
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
                }
            }
            .padding(.vertical, 4)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } header: {
            Text("Your Spaces")
                .font(.title2).bold()
                .foregroundStyle(Color(.label))
                .textCase(nil)
        }
    }

    // MARK: Recently Accessed

    @ViewBuilder
    private var recentlyAccessedSection: some View {
        let items = recentItems
        if !items.isEmpty {
            Section {
                ForEach(items) { item in
                    Button { selectedItem = item } label: {
                        RecentlyAccessedRow(item: item)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets())
                }
            } header: {
                Text("Recently Accessed")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color(.secondaryLabel))
                    .textCase(nil)
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

                    Spacer()

                    Text(reason.label)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(reason.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(reason.color.opacity(0.12))
                        .clipShape(Capsule())
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
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    private var locationPath: String {
        guard let location = item.location else { return "" }
        var parts: [String] = []
        var current: Location? = location
        var depth = 0
        while let loc = current, depth < 50 {
            parts.insert(loc.name, at: 0)
            current = loc.parent
            depth += 1
        }
        return parts.joined(separator: " › ")
    }
}

// MARK: - Search location row

private struct SearchLocationRow: View {
    let location: Location
    let onTap: () -> Void

    private var areaColor: Color {
        rootAreaColor(for: location) ?? .teal
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                LocationIconView(
                    icon: location.icon ?? "folder.fill",
                    font: .body,
                    color: location.icon != nil ? areaColor : Color(.secondaryLabel)
                )
                .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(location.name)
                        .font(.headline)
                        .foregroundStyle(Color(.label))
                    if !ancestorPath.isEmpty {
                        Text(ancestorPath)
                            .font(.caption)
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Full path of ancestors above this location, e.g. "Kitchen › Cupboards".
    /// Empty if this is a root area.
    private var ancestorPath: String {
        var parts: [String] = []
        var current: Location? = location.parent
        while let loc = current {
            parts.insert(loc.name, at: 0)
            current = loc.parent
        }
        return parts.joined(separator: " › ")
    }
}

// MARK: - Recently Accessed row

private struct RecentlyAccessedRow: View {
    let item: Item

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.subheadline)
                    .foregroundStyle(Color(.label))
                if !locationPath.isEmpty {
                    Text(locationPath)
                        .font(.system(size: 10))
                        .foregroundStyle(Color(.secondaryLabel))
                }
            }

            Spacer()

            if let qty = item.quantity {
                Text(item.unit.map { "\(qty) \($0)" } ?? "\(qty)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color(.secondaryLabel))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    private var locationPath: String {
        guard let location = item.location else { return "" }
        var parts: [String] = []
        var current: Location? = location
        var depth = 0
        while let loc = current, depth < 50 {
            parts.insert(loc.name, at: 0)
            current = loc.parent
            depth += 1
        }
        return parts.joined(separator: " › ")
    }
}
