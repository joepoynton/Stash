//
//  LocationDetailSheet.swift
//  Stash

import SwiftUI
import SwiftData

struct LocationDetailSheet: View {
    @Bindable var location: Location

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(StoreKitManager.self) private var storeKit

    @State private var showMoveSheet = false
    @State private var showPhotoUpgradePrompt = false
    @State private var pickerExpandedIDs: Set<UUID> = []
    @State private var showDeleteActionSheet = false
    @State private var showCascadeConfirm = false
    @State private var showEmptyDeleteConfirm = false
    @State private var showCycleAlert = false
    @State private var showCamera = false
    @State private var showLibraryPicker = false
    @State private var showPhotoSourceOptions = false

    var body: some View {
        NavigationStack {
            formContent
                .navigationTitle("Edit Space")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            .sheet(isPresented: $showMoveSheet) {
                LocationPickerSheet(
                    title: "Move to…",
                    excludedIDs: selfAndDescendantIDs,
                    allowTopLevel: true,
                    expandedIDs: $pickerExpandedIDs,
                    onSelect: { newParent in
                        // Cycle guard: belt-and-suspenders check in case the picker's
                        // exclusion list was bypassed.
                        if let newParent, selfAndDescendantIDs.contains(newParent.id) {
                            showCycleAlert = true
                            return
                        }
                        location.parent = newParent
                    }
                )
            }
            .alert("Cannot move here", isPresented: $showCycleAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("A space cannot be moved inside itself.")
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraView { data in
                    Task {
                        if let compressed = await ImageCompressor.compress(data) {
                            location.photo = compressed
                            ThumbnailCache.shared.invalidate(id: location.id)
                        }
                    }
                }
                .ignoresSafeArea()
            }
            .confirmationDialog("Photo", isPresented: $showPhotoSourceOptions, titleVisibility: .hidden) {
                Button("Take Photo") { showCamera = true }
                Button("Choose from Library") { showLibraryPicker = true }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showLibraryPicker) {
                LibraryPickerView { data in
                    Task {
                        if let compressed = await ImageCompressor.compress(data) {
                            location.photo = compressed
                            ThumbnailCache.shared.invalidate(id: location.id)
                        }
                    }
                }
                .ignoresSafeArea()
            }
            .confirmationDialog(
                "Delete \"\(location.name)\"?",
                isPresented: $showDeleteActionSheet,
                titleVisibility: .visible
            ) {
                Button("Delete everything inside", role: .destructive) {
                    showCascadeConfirm = true
                }
                Button("Move contents to \(location.parent?.name ?? "Top Level")") {
                    moveContentsToParent()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Are you sure?", isPresented: $showCascadeConfirm) {
                Button("Delete everything", role: .destructive) {
                    Haptics.write()
                    cascadeDelete(location)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone.")
            }
            .alert("Delete \"\(location.name)\"?", isPresented: $showEmptyDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    Haptics.write()
                    modelContext.delete(location)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone.")
            }
            .sheet(isPresented: $showPhotoUpgradePrompt) {
                UpgradePromptSheet(message: "Unlock Stash Pro to add photos to your items and locations.")
            }
        }
    }

    // MARK: - Form content

    @ViewBuilder
    private var formContent: some View {
        Form {
            Section {
                TextField("Name", text: $location.name)
            }

            Section("Icon") {
                SymbolPickerView(selected: $location.icon)
                    .padding(.vertical, 4)
            }

            if location.isRoot {
                Section("Colour") {
                    colorSwatches
                        .padding(.vertical, 4)
                    ColorPicker("Custom colour", selection: colorPickerBinding, supportsOpacity: false)
                }
            }

            // Photo
            Section("Photo") {
                if let data = location.photo, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .aspectRatio(3/2, contentMode: .fit)
                        .clipped()
                        .listRowInsets(EdgeInsets())

                    Button {
                        if storeKit.isPro {
                            showPhotoSourceOptions = true
                        } else {
                            showPhotoUpgradePrompt = true
                        }
                    } label: {
                        Label("Replace Photo", systemImage: storeKit.isPro ? "camera" : "lock.fill")
                            .foregroundStyle(.teal)
                    }
                    Button("Remove Photo", role: .destructive) {
                        location.photo = nil
                        ThumbnailCache.shared.invalidate(id: location.id)
                    }
                } else {
                    Button {
                        if storeKit.isPro {
                            showPhotoSourceOptions = true
                        } else {
                            showPhotoUpgradePrompt = true
                        }
                    } label: {
                        Label("Add Photo", systemImage: storeKit.isPro ? "camera" : "lock.fill")
                            .foregroundStyle(storeKit.isPro ? .teal : Color(.secondaryLabel))
                    }
                }
            }

            Section {
                Button {
                    showMoveSheet = true
                } label: {
                    Label("Move to…", systemImage: "arrow.up.arrow.down")
                        .foregroundStyle(.teal)
                }
            }

            Section {
                Button("Delete Space", role: .destructive) {
                    if location.childList.isEmpty && location.itemList.isEmpty {
                        showEmptyDeleteConfirm = true
                    } else {
                        showDeleteActionSheet = true
                    }
                }
            }
        }
    }

    // MARK: - Colour picker binding

    private var colorPickerBinding: Binding<Color> {
        Binding(
            get: {
                guard let hex = location.color else { return Color(hex: "#808080") ?? .gray }
                return Color(hex: hex) ?? .teal
            },
            set: { newColor in
                location.color = newColor.toHex()
            }
        )
    }

    // MARK: - Colour swatches

    private var colorSwatches: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 10) {
            Button {
                location.color = nil
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.systemGray3), lineWidth: 1.5)
                        .frame(width: 44, height: 44)
                    if location.color == nil {
                        Image(systemName: "checkmark")
                            .font(.caption.bold())
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                }
            }
            .buttonStyle(.plain)

            ForEach(AreaPalette.colors, id: \.hex) { swatch in
                Button {
                    location.color = swatch.hex
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(hex: swatch.hex) ?? .teal)
                            .frame(width: 44, height: 44)
                        if location.color == swatch.hex {
                            Image(systemName: "checkmark")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Helpers

    private var selfAndDescendantIDs: Set<UUID> {
        location.selfAndDescendantIDs
    }

    private func cascadeDelete(_ loc: Location) {
        modelContext.cascadeDelete(loc)
    }

    private func moveContentsToParent() {
        let dest = location.parent
        for child in location.childList { child.parent = dest }
        // When deleting a root Area, dest is nil — items can't live at the
        // top level, so park them in the "Unsorted" Area instead.
        let items = location.itemList
        if !items.isEmpty {
            let itemDest = dest ?? Location.unsortedArea(in: modelContext, excluding: location.id)
            for item in items { item.location = itemDest }
        }
        modelContext.delete(location)
    }
}
