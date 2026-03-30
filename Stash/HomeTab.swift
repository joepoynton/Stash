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

    var label: String {
        switch self {
        case .lowStock:     "Low stock"
        case .expiringSoon: "Expires soon"
        case .notVerified:  "Not verified"
        }
    }

    var color: Color {
        switch self {
        case .lowStock:     .teal
        case .expiringSoon: .orange
        case .notVerified:  Color(.secondaryLabel)
        }
    }
}

// MARK: - HomeTab

struct HomeTab: View {
    @Query(sort: \Location.dateCreated) private var allLocations: [Location]
    @Query private var allItems: [Item]

    @Environment(NavigationState.self) private var navState
    @Environment(RecentlyAccessedStore.self) private var recentStore

    @AppStorage("staleThresholdDays") private var staleThresholdDays = 90

    @State private var showSettings = false
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
            if item.orderStatus == .low {
                return (item, .lowStock)
            }
            if let expiry = item.expiryDate, expiry <= expiryThreshold {
                return (item, .expiringSoon)
            }
            if item.lastVerified <= staleThreshold {
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
                    Button { showSettings = true } label: {
                        Image(systemName: "gear")
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(item: $selectedItem) {
            ItemDetailSheet(item: $0)
        }
    }

    // MARK: Search

    private var filteredItems: [Item] {
        let q = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return allItems.filter { itemMatchesSearch($0, query: q) }
    }

    private func itemMatchesSearch(_ item: Item, query: String) -> Bool {
        if item.name.lowercased().contains(query) { return true }
        if let notes = item.notes, notes.lowercased().contains(query) { return true }
        var current: Location? = item.location
        while let loc = current {
            if loc.name.lowercased().contains(query) { return true }
            current = loc.parent
        }
        return false
    }

    @ViewBuilder
    private var searchResultsContent: some View {
        let results = filteredItems
        if results.isEmpty {
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
                LazyVStack(spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                        SearchResultRow(item: item, onTap: { selectedItem = item })
                        if index < results.count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)
                .padding(.top, 8)
            }
        }
    }

    // MARK: Main content

    private var mainContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                needsAttentionSection
                recentlyAccessedSection
                yourSpacesSection
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
    }

    // MARK: Needs Attention

    @ViewBuilder
    private var needsAttentionSection: some View {
        let items = needsAttentionItems
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Needs Attention")
                    .font(.title2).bold()

                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.item.id) { index, entry in
                        Button { selectedItem = entry.item } label: {
                            NeedsAttentionRow(item: entry.item, reason: entry.reason)
                        }
                        .buttonStyle(.plain)

                        if index < items.count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: Recently Accessed

    @ViewBuilder
    private var recentlyAccessedSection: some View {
        let items = recentItems
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recently Accessed")
                    .font(.title2).bold()

                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        Button { selectedItem = item } label: {
                            RecentlyAccessedRow(item: item)
                        }
                        .buttonStyle(.plain)

                        if index < items.count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: Your Spaces

    private var yourSpacesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Spaces")
                .font(.title2).bold()

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
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "archivebox")
                .font(.system(size: 52))
                .foregroundStyle(Color(.tertiaryLabel))
            VStack(spacing: 6) {
                Text("Start by adding your spaces")
                    .font(.headline)
                Text("Where do you keep things? Garage, loft, car — add them here.")
                    .font(.subheadline)
                    .foregroundStyle(Color(.secondaryLabel))
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding()
    }
}

// MARK: - Needs Attention row

private struct NeedsAttentionRow: View {
    let item: Item
    let reason: AttentionReason

    var body: some View {
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
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var locationPath: String {
        guard let location = item.location else { return "" }
        var parts: [String] = []
        var current: Location? = location
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

            if let qty = item.quantity {
                Text(item.unit.map { "\(qty) \($0)" } ?? "\(qty)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Color(.secondaryLabel))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var locationPath: String {
        guard let location = item.location else { return "" }
        var parts: [String] = []
        var current: Location? = location
        while let loc = current {
            parts.insert(loc.name, at: 0)
            current = loc.parent
        }
        return parts.joined(separator: " › ")
    }
}
