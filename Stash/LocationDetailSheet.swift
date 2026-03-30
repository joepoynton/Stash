//
//  LocationDetailSheet.swift
//  Stash

import SwiftUI
import SwiftData
import PhotosUI

struct LocationDetailSheet: View {
    @Bindable var location: Location

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var showMoveSheet = false
    @State private var showDeleteActionSheet = false
    @State private var showCascadeConfirm = false
    @State private var showEmptyDeleteConfirm = false
    @State private var showPhotoOptions = false
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem? = nil

    static let areaColors: [(name: String, hex: String)] = [
        ("Teal",   "#2A9D8F"), ("Blue",   "#3A86FF"), ("Purple", "#8338EC"),
        ("Pink",   "#FF006E"), ("Orange", "#FB5607"), ("Yellow", "#FFBE0B"),
        ("Green",  "#06D6A0"), ("Red",    "#E63946")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $location.name)
                }

                if location.isRoot {
                    Section("Icon") {
                        SymbolPickerView(selected: $location.icon)
                            .padding(.vertical, 4)
                    }
                    Section("Colour") {
                        colorSwatches
                            .padding(.vertical, 4)
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
                            showPhotoOptions = true
                        } label: {
                            Label("Replace Photo", systemImage: "camera")
                                .foregroundStyle(.teal)
                        }

                        Button("Remove Photo", role: .destructive) {
                            location.photo = nil
                        }
                    } else {
                        Button {
                            showPhotoOptions = true
                        } label: {
                            Label("Add Photo", systemImage: "camera")
                                .foregroundStyle(.teal)
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
                    onSelect: { newParent in
                        location.parent = newParent
                    }
                )
            }
            .sheet(isPresented: $showCamera) {
                CameraCapture { image in
                    if let data = ImageCompressor.compress(image) {
                        location.photo = data
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
                        location.photo = compressed
                    }
                    selectedPhotoItem = nil
                }
            }
            .confirmationDialog("Photo", isPresented: $showPhotoOptions) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Take Photo") { showCamera = true }
                }
                Button("Choose from Library") { showPhotoPicker = true }
                Button("Cancel", role: .cancel) {}
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
                    cascadeDelete(location)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone.")
            }
            .alert("Delete \"\(location.name)\"?", isPresented: $showEmptyDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    modelContext.delete(location)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone.")
            }
        }
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

            ForEach(Self.areaColors, id: \.hex) { swatch in
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
        var ids = Set<UUID>()
        collectIDs(of: location, into: &ids)
        return ids
    }

    private func collectIDs(of loc: Location, into ids: inout Set<UUID>) {
        ids.insert(loc.id)
        for child in loc.childList { collectIDs(of: child, into: &ids) }
    }

    private func cascadeDelete(_ loc: Location) {
        for child in loc.childList { cascadeDelete(child) }
        modelContext.delete(loc)
    }

    private func moveContentsToParent() {
        let dest = location.parent
        for child in location.childList { child.parent = dest }
        for item  in location.itemList  { item.location = dest }
        modelContext.delete(location)
    }
}
