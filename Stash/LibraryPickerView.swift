//
//  LibraryPickerView.swift
//  Stash

import SwiftUI
import PhotosUI

struct LibraryPickerView: UIViewControllerRepresentable {
    let onImagePicked: (Data) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 1
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onImagePicked: onImagePicked) }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onImagePicked: (Data) -> Void
        init(onImagePicked: @escaping (Data) -> Void) { self.onImagePicked = onImagePicked }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let result = results.first else { return }
            result.itemProvider.loadDataRepresentation(forTypeIdentifier: "public.image") { [weak self] data, _ in
                guard let data, let self else { return }
                DispatchQueue.main.async {
                    self.onImagePicked(data)
                }
            }
        }
    }
}
