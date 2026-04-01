//
//  ItemDetailSheet.swift
//  Stash

import SwiftUI
import SwiftData
import PhotosUI

struct ItemDetailSheet: View {
    @Bindable var item: Item

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(RecentlyAccessedStore.self) private var recentStore

    @State private var showMoveSheet = false
    @State private var showDeleteConfirm = false
    @State private var showPhotoOptions = false
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var showFullscreenPhoto = false

    // Quantity tracking
    @State private var showTurnOffQuantityConfirm = false
    @State private var editingQuantity = false
    @State private var quantityEntryText = ""
    @FocusState private var quantityFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                // Photo — full-width 3:2, camera icon to add/replace, tap to fullscreen
                Section {
                    photoSection
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)

                // On-order banner
                if item.orderStatus == .onOrder {
                    Section {
                        Label("On its way", systemImage: "shippingbox.fill")
                            .foregroundStyle(.orange)
                            .fontWeight(.medium)
                    }
                }

                // Name
                Section {
                    TextField("Name", text: $item.name)
                        .font(.headline)
                }

                // Location + Move
                Section {
                    HStack {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(Color(.secondaryLabel))
                            .frame(width: 24)
                        Text(locationPath)
                            .foregroundStyle(Color(.label))
                    }
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

                        let expiringSoon = (item.expiryDate ?? .distantFuture).timeIntervalSinceNow < 30 * 86400
                        if expiringSoon {
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
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                recentStore.record(itemID: item.id)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                // Done button above the number pad — only visible when editing quantity
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    if editingQuantity {
                        Button("Done") { commitQuantityEntry() }
                    }
                }
            }
            .onChange(of: quantityFieldFocused) { _, isFocused in
                // Commit if focus moves away from the quantity field
                if !isFocused && editingQuantity {
                    commitQuantityEntry()
                }
            }
            .sheet(isPresented: $showMoveSheet) {
                LocationPickerSheet(
                    title: "Move to…",
                    excludedIDs: [],
                    allowTopLevel: false,
                    onSelect: { newLocation in
                        if let loc = newLocation {
                            item.location = loc
                            item.lastVerified = Date()
                        }
                    }
                )
            }
            .sheet(isPresented: $showCamera) {
                CameraCapture { image in
                    if let data = ImageCompressor.compress(image) {
                        item.photo = data
                    }
                }
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images)
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data),
                       let compressed = ImageCompressor.compress(image) {
                        item.photo = compressed
                    }
                    selectedPhotoItem = nil
                }
            }
            .sheet(isPresented: $showPhotoOptions) {
                PhotoSourceSheet(
                    hasPhoto: item.photo != nil,
                    onCamera:  { showCamera      = true },
                    onLibrary: { showPhotoPicker = true },
                    onRemove:  { item.photo      = nil  }
                )
            }
            .fullScreenCover(isPresented: $showFullscreenPhoto) {
                FullscreenPhotoView(imageData: item.photo)
            }
            .alert("Delete \"\(item.name)\"?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
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

                // Camera icon to replace photo
                Button {
                    showPhotoOptions = true
                } label: {
                    Image(systemName: "camera.fill")
                        .font(.caption)
                        .padding(8)
                        .background(.thinMaterial)
                        .clipShape(Circle())
                        .foregroundStyle(Color(.label))
                }
                .buttonStyle(.plain)
                .padding(8)
            } else {
                // Placeholder — discoverable camera icon, tap to add
                Button {
                    showPhotoOptions = true
                } label: {
                    Color(.systemGray6)
                        .aspectRatio(3/2, contentMode: .fit)
                        .overlay {
                            Image(systemName: "camera")
                                .font(.title2)
                                .foregroundStyle(Color(.tertiaryLabel))
                        }
                }
                .buttonStyle(.plain)
            }
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
                // +  /  tappable number  /  −
                HStack {
                    Button {
                        item.decrementQuantity()
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title2)
                            .foregroundStyle((item.quantity ?? 0) == 0 ? Color(.tertiaryLabel) : .teal)
                    }
                    .buttonStyle(.plain)
                    .disabled((item.quantity ?? 0) == 0)

                    Spacer()

                    quantityDisplay

                    Spacer()

                    Button {
                        item.incrementQuantity()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.teal)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)

                // Unit
                HStack {
                    Text("Unit")
                    Spacer()
                    TextField("e.g. rolls, tablets", text: unitBinding)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 160)
                }

                // Minimum
                Stepper(
                    "Minimum: \(item.minimumQuantity ?? 0)",
                    value: Binding(
                        get: { item.minimumQuantity ?? 0 },
                        set: { item.minimumQuantity = $0 > 0 ? $0 : nil }
                    ),
                    in: 0...9999
                )

                // Stock status badge
                switch item.orderStatus {
                case .low:
                    Label("Low stock", systemImage: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.teal)
                case .onOrder:
                    Label("On order", systemImage: "shippingbox")
                        .font(.caption)
                        .foregroundStyle(.orange)
                case .normal:
                    EmptyView()
                }
            }
        }
    }

    // The centre of the +/- row. Tapping the number switches to an inline
    // TextField with a number pad; committing restores the display.
    @ViewBuilder
    private var quantityDisplay: some View {
        if editingQuantity {
            TextField("0", text: $quantityEntryText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.title.monospacedDigit())
                .focused($quantityFieldFocused)
                .frame(minWidth: 60)
        } else {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(item.quantity ?? 0)")
                    .font(.title.monospacedDigit())
                    .foregroundStyle(Color(.label))
                    .underline(color: Color(.tertiaryLabel))   // subtle tap hint
                if let unit = item.unit, !unit.isEmpty {
                    Text(unit)
                        .font(.title3)
                        .foregroundStyle(Color(.secondaryLabel))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                quantityEntryText = "\(item.quantity ?? 0)"
                editingQuantity = true
                quantityFieldFocused = true
            }
        }
    }

    // MARK: - Helpers

    private func commitQuantityEntry() {
        guard editingQuantity else { return }
        if let value = Int(quantityEntryText) {
            item.updateQuantity(to: max(0, value))
        }
        editingQuantity = false
        quantityEntryText = ""
        quantityFieldFocused = false
    }

    private var unitBinding: Binding<String> {
        Binding(
            get: { item.unit ?? "" },
            set: { item.unit = $0.isEmpty ? nil : String($0.prefix(20)) }
        )
    }

    private var locationPath: String {
        guard let location = item.location else { return "No location" }
        var parts: [String] = []
        var current: Location? = location
        while let loc = current {
            parts.insert(loc.name, at: 0)
            current = loc.parent
        }
        return parts.joined(separator: " › ")
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
