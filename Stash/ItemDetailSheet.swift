//
//  ItemDetailSheet.swift
//  Stash

import SwiftUI
import SwiftData

struct ItemDetailSheet: View {
    @Bindable var item: Item

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(RecentlyAccessedStore.self) private var recentStore
    @Environment(StoreKitManager.self) private var storeKit
    @Environment(NavigationState.self) private var navState

    @State private var showMoveSheet = false
    @State private var showPhotoUpgradePrompt = false
    @State private var pickerExpandedIDs: Set<UUID> = []
    @State private var showDeleteConfirm = false
    @State private var showMarkArrivedConfirm = false
    @State private var showCamera = false
    @State private var showLibraryPicker = false
    @State private var showPhotoSourceOptions = false
    @State private var showPhotoActions = false
    @State private var showFullscreenPhoto = false

    // Quantity tracking
    @State private var showTurnOffQuantityConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                // Photo — full-width 3:2, camera icon to add/replace, tap to fullscreen
                Section {
                    photoSection
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)

                // On-order banner — tappable so the order can be cleared from here
                if item.orderStatus == .onOrder {
                    onOrderBanner
                }

                // Name
                Section {
                    TextField("Name", text: $item.name)
                        .font(.headline)
                }

                // Location + Move — tapping the path jumps to the location in Browse
                Section {
                    Button {
                        goToLocation()
                    } label: {
                        HStack {
                            Image(systemName: "mappin.and.ellipse")
                                .foregroundStyle(Color(.secondaryLabel))
                                .frame(width: 24)
                            Text(locationPath)
                                .foregroundStyle(rootAreaColor(for: item.location) ?? Color(.label))
                                .multilineTextAlignment(.leading)
                            Spacer()
                            if item.location != nil {
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color(.tertiaryLabel))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(item.location == nil)
                    Button {
                        showMoveSheet = true
                    } label: {
                        Label("Move to…", systemImage: "arrow.up.arrow.down")
                            .foregroundStyle(.teal)
                    }
                }

                // Out of place
                Section {
                    Toggle("Out of place", isOn: $item.isOutOfPlace)
                        .tint(.teal)
                        .onChange(of: item.isOutOfPlace) { _, newValue in
                            Haptics.write()
                            if !newValue { item.outOfPlaceNote = nil }
                        }
                    if item.isOutOfPlace {
                        TextField("Note (optional)", text: outOfPlaceNoteBinding)
                    }
                }

                // Notes
                Section("Notes") {
                    TextField("Add notes…", text: notesBinding, axis: .vertical)
                        .lineLimit(3...8)
                }

                // Quantity — toggle always visible; controls expand when tracking is on
                quantitySection

                // Restock — only shown when quantity tracking is on
                if item.quantity != nil {
                    Section {
                        Button {
                            Haptics.write()
                            item.manuallyRestocking.toggle()
                        } label: {
                            Label(
                                item.manuallyRestocking ? "Remove from Restock" : "Add to Restock",
                                systemImage: item.manuallyRestocking ? "cart.badge.minus" : "cart.badge.plus"
                            )
                            .foregroundStyle(item.manuallyRestocking ? Color(.secondaryLabel) : .teal)
                        }
                    }
                }

                // Expiry
                Section {
                    Toggle("Track expiry date", isOn: Binding(
                        get: { item.expiryDate != nil },
                        set: { item.expiryDate = $0 ? (item.expiryDate ?? Date()) : nil }
                    ))

                    if item.expiryDate != nil {
                        DatePicker(
                            "Expiry date",
                            selection: Binding(
                                get: { item.expiryDate ?? Date() },
                                set: { item.expiryDate = $0 }
                            ),
                            displayedComponents: .date
                        )

                        let timeToExpiry = (item.expiryDate ?? .distantFuture).timeIntervalSinceNow
                        if timeToExpiry < 0 {
                            Label("Expired", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else if timeToExpiry < 30 * 86400 {
                            Label("Expires soon", systemImage: "exclamationmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                // Verification + dates
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Last verified")
                                .font(.caption)
                                .foregroundStyle(Color(.secondaryLabel))
                            Text(item.lastVerified.relativeDescription)
                                .font(.subheadline)
                        }
                        Spacer()
                        Button("Mark as Verified") {
                            Haptics.write()
                            item.markAsVerified()
                        }
                        .buttonStyle(.bordered)
                        .tint(.teal)
                    }
                    Text("Added \(item.dateAdded.formatted(date: .long, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(Color(.secondaryLabel))

                    Toggle(isOn: $item.neverStale) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Always verified")
                            Text("This item will never be flagged as out of date")
                                .font(.caption)
                                .foregroundStyle(Color(.secondaryLabel))
                        }
                    }
                    .tint(.teal)
                }

                // Delete
                Section {
                    Button("Delete Item", role: .destructive) {
                        showDeleteConfirm = true
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            // iOS 27 View Annotations seam: this sheet *is* the item, so
            // "move this to the loft" / "I've used two of these" resolve here.
            .stashItemContext(item)
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                recentStore.record(itemID: item.id)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showMoveSheet) {
                LocationPickerSheet(
                    title: "Move to…",
                    excludedIDs: [],
                    allowTopLevel: false,
                    expandedIDs: $pickerExpandedIDs,
                    onSelect: { newLocation in
                        if let loc = newLocation {
                            item.location = loc
                            item.lastVerified = Date()
                        }
                    }
                )
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraView { data in
                    Task {
                        if let compressed = await ImageCompressor.compress(data) {
                            item.photo = compressed
                            ThumbnailCache.shared.invalidate(id: item.id)
                        }
                    }
                }
                .ignoresSafeArea()
            }
            .confirmationDialog("Photo", isPresented: $showPhotoActions, titleVisibility: .hidden) {
                Button("Take Photo") { showCamera = true }
                Button("Choose from Library") { showLibraryPicker = true }
                Button("Remove Photo", role: .destructive) {
                    item.photo = nil
                    ThumbnailCache.shared.invalidate(id: item.id)
                }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Add Photo", isPresented: $showPhotoSourceOptions, titleVisibility: .hidden) {
                Button("Take Photo") { showCamera = true }
                Button("Choose from Library") { showLibraryPicker = true }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showLibraryPicker) {
                LibraryPickerView { data in
                    Task {
                        if let compressed = await ImageCompressor.compress(data) {
                            item.photo = compressed
                            ThumbnailCache.shared.invalidate(id: item.id)
                        }
                    }
                }
                .ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $showFullscreenPhoto) {
                FullscreenPhotoView(imageData: item.photo)
            }
            .alert("Delete \"\(item.name)\"?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    Haptics.write()
                    modelContext.delete(item)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone.")
            }
            .alert("Turn off quantity tracking?", isPresented: $showTurnOffQuantityConfirm) {
                Button("Turn Off", role: .destructive) {
                    item.quantity = nil
                    item.unit = nil
                    item.minimumQuantity = nil
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The current quantity, unit, and minimum will be cleared.")
            }
        }
    }

    // MARK: - On-order banner

    private var onOrderBanner: some View {
        Section {
            Button {
                showMarkArrivedConfirm = true
            } label: {
                HStack {
                    Label("On its way", systemImage: "shippingbox.fill")
                        .foregroundStyle(StatusColor.onOrder.color)
                        .fontWeight(.medium)
                    Spacer()
                    Text("Arrived?")
                        .font(.subheadline)
                        .foregroundStyle(.teal)
                }
            }
            .buttonStyle(.plain)
            .alert("Mark as arrived?", isPresented: $showMarkArrivedConfirm) {
                Button("Mark as Arrived") {
                    Haptics.write()
                    // Count 0: the order status clears; the quantity controls
                    // below are the place to record how many actually arrived.
                    item.markAsArrived(count: 0)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This clears the on-order status. Update the quantity below once you've put the items away.")
            }
        }
    }

    // MARK: - Photo section

    @ViewBuilder
    private var photoSection: some View {
        ZStack(alignment: .bottomTrailing) {
            if let data = item.photo, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .aspectRatio(3/2, contentMode: .fit)
                    .clipped()
                    .contentShape(Rectangle())
                    .onTapGesture { showFullscreenPhoto = true }

                // Camera/lock icon to replace/remove photo
                Button {
                    if storeKit.isPro {
                        showPhotoActions = true
                    } else {
                        showPhotoUpgradePrompt = true
                    }
                } label: {
                    Image(systemName: storeKit.isPro ? "camera.fill" : "lock.fill")
                        .font(.caption)
                        .padding(8)
                        .background(.thinMaterial)
                        .clipShape(Circle())
                        .foregroundStyle(Color(.label))
                }
                .buttonStyle(.plain)
                .padding(8)
            } else {
                // Placeholder — camera or lock icon depending on tier
                Button {
                    if storeKit.isPro {
                        showPhotoSourceOptions = true
                    } else {
                        showPhotoUpgradePrompt = true
                    }
                } label: {
                    Color(.systemGray6)
                        .aspectRatio(3/2, contentMode: .fit)
                        .overlay {
                            Image(systemName: storeKit.isPro ? "camera" : "lock.fill")
                                .font(.title2)
                                .foregroundStyle(Color(.tertiaryLabel))
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showPhotoUpgradePrompt) {
            UpgradePromptSheet(message: "Unlock Stash Pro to add photos to your items and locations.")
        }
    }

    // MARK: - Quantity section

    private var quantitySection: some View {
        Section("Quantity") {
            // Toggle — always visible. Turning off requires confirmation.
            Toggle("Track quantity", isOn: Binding(
                get: { item.quantity != nil },
                set: { newValue in
                    if newValue {
                        item.quantity = 0
                    } else {
                        showTurnOffQuantityConfirm = true
                        // item.quantity stays non-nil until the alert confirms,
                        // so the toggle springs back to ON automatically.
                    }
                }
            ))
            .tint(.teal)

            if item.quantity != nil {
                // Current quantity — shared tap-to-type +/- control
                NumericEntryField(
                    value: Binding(
                        get: { item.quantity ?? 0 },
                        // Route through updateQuantity so lastVerified and the
                        // auto-clear of a stale on-order flag still fire.
                        set: { item.updateQuantity(to: $0) }
                    ),
                    range: 0...9_999,
                    unit: item.unit
                )
                .padding(.vertical, 4)

                // Unit
                HStack {
                    Text("Unit")
                    Spacer()
                    TextField("e.g. rolls, tablets", text: unitBinding)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 160)
                }

                // Minimum — compact +/- after the label (0 = no minimum)
                HStack {
                    Text("Minimum")
                        .foregroundStyle(Color(.label))
                    Spacer()
                    NumericEntryField(
                        value: Binding(
                            get: { item.minimumQuantity ?? 0 },
                            set: { item.minimumQuantity = $0 > 0 ? $0 : nil }
                        ),
                        range: 0...9_999,
                        prominent: false
                    )
                }
                .padding(.vertical, 4)

                // Stock status badge (C1 colours)
                switch item.orderStatus {
                case .low:
                    StatusBadge(
                        text: StatusColor.lowStock.label,
                        color: StatusColor.lowStock.color,
                        systemImage: "exclamationmark.circle.fill"
                    )
                case .onOrder:
                    StatusBadge(
                        text: StatusColor.onOrder.label,
                        color: StatusColor.onOrder.color,
                        systemImage: "shippingbox"
                    )
                case .normal:
                    EmptyView()
                }
            }
        }
    }

    // MARK: - Helpers

    /// Deep-links into the Browse tab at the item's location and closes the sheet.
    private func goToLocation() {
        guard let location = item.location else { return }
        navState.browseNavigationPath = location.ancestorChain
        navState.selectedTab = 1
        dismiss()
    }

    private var unitBinding: Binding<String> {
        Binding(
            get: { item.unit ?? "" },
            set: { item.unit = $0.isEmpty ? nil : String($0.prefix(20)) }
        )
    }

    private var locationPath: String {
        item.location?.pathString ?? "No location"
    }

    private var notesBinding: Binding<String> {
        Binding(
            get: { item.notes ?? "" },
            set: { item.notes = $0.isEmpty ? nil : $0 }
        )
    }

    private var outOfPlaceNoteBinding: Binding<String> {
        Binding(
            get: { item.outOfPlaceNote ?? "" },
            set: { item.outOfPlaceNote = $0.isEmpty ? nil : $0 }
        )
    }
}

// MARK: - Fullscreen Photo View

struct FullscreenPhotoView: View {
    let imageData: Data?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            if let data = imageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.black.opacity(0.5))
                    .padding()
            }
        }
    }
}

// MARK: - Date helper

private extension Date {
    var relativeDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
