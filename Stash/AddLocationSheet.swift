//
//  AddLocationSheet.swift
//  Stash

import SwiftUI
import SwiftData
import PhotosUI

struct AddLocationSheet: View {
    /// nil = creating a root Area; non-nil = creating a child space inside this location.
    let parentLocation: Location?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var selectedIcon: String? = "archivebox.fill"
    @State private var selectedColorHex: String? = nil
    @State private var photoData: Data? = nil
    @State private var photoSkipped = false
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem? = nil

    @FocusState private var nameFocused: Bool

    private var isRoot: Bool { parentLocation == nil }

    static let areaColors: [(name: String, hex: String)] = [
        ("Teal",   "#2A9D8F"), ("Blue",   "#3A86FF"), ("Purple", "#8338EC"),
        ("Pink",   "#FF006E"), ("Orange", "#FB5607"), ("Yellow", "#FFBE0B"),
        ("Green",  "#06D6A0"), ("Red",    "#E63946")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .focused($nameFocused)
                }

                if isRoot {
                    Section("Icon") {
                        SymbolPickerView(selected: $selectedIcon)
                            .padding(.vertical, 4)
                    }

                    Section("Colour") {
                        colorSwatches
                            .padding(.vertical, 4)
                    }
                }

                // Photo prompt — encouraged
                if !photoSkipped || photoData != nil {
                    Section {
                        photoPrompt
                    }
                }
            }
            .navigationTitle(isRoot ? "New Area" : "New Space")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { nameFocused = true }
            .sheet(isPresented: $showCamera) {
                CameraCapture { image in
                    if let data = ImageCompressor.compress(image) {
                        photoData = data
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
                        photoData = compressed
                    }
                    selectedPhotoItem = nil
                }
            }
        }
    }

    // MARK: - Photo prompt

    @ViewBuilder
    private var photoPrompt: some View {
        if let data = photoData, let uiImage = UIImage(data: data) {
            // Photo selected — show preview with change/remove options
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .aspectRatio(3/2, contentMode: .fit)
                .clipped()
                .listRowInsets(EdgeInsets())

            Button {
                showPhotoPicker = true
            } label: {
                Label("Change Photo", systemImage: "camera")
                    .foregroundStyle(.teal)
            }

            Button("Remove Photo", role: .destructive) {
                photoData = nil
            }
        } else {
            // Prompt — camera, library, skip
            VStack(alignment: .center, spacing: 14) {
                Image(systemName: "camera.fill")
                    .font(.title2)
                    .foregroundStyle(.teal)

                Text("Add a photo of this space?")
                    .font(.subheadline)
                    .foregroundStyle(Color(.label))

                HStack(spacing: 12) {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button {
                            showCamera = true
                        } label: {
                            Label("Camera", systemImage: "camera")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.teal)
                    }

                    Button {
                        showPhotoPicker = true
                    } label: {
                        Label("Library", systemImage: "photo")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.teal)
                }

                Button("Skip") {
                    photoSkipped = true
                }
                .font(.subheadline)
                .foregroundStyle(Color(.secondaryLabel))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Colour swatches

    private var colorSwatches: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 10) {
            // "None" swatch
            Button {
                selectedColorHex = nil
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.systemGray3), lineWidth: 1.5)
                        .frame(width: 44, height: 44)
                    if selectedColorHex == nil {
                        Image(systemName: "checkmark")
                            .font(.caption.bold())
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                }
            }
            .buttonStyle(.plain)

            ForEach(Self.areaColors, id: \.hex) { swatch in
                Button {
                    selectedColorHex = swatch.hex
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(hex: swatch.hex) ?? .teal)
                            .frame(width: 44, height: 44)
                        if selectedColorHex == swatch.hex {
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

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let location = Location(
            name: trimmed,
            icon: isRoot ? selectedIcon : nil,
            color: isRoot ? selectedColorHex : nil,
            parent: parentLocation
        )
        location.photo = photoData
        modelContext.insert(location)
        dismiss()
    }
}
