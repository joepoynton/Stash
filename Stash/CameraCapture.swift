//
//  CameraCapture.swift
//  Stash
//
//  UIViewControllerRepresentable wrapping UIImagePickerController for camera capture.
//  Use UIImagePickerController.isSourceTypeAvailable(.camera) before presenting.
//

import SwiftUI
import UIKit

private class PortraitImagePickerController: UIImagePickerController {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
}

struct CameraCapture: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = PortraitImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraCapture
        init(_ parent: CameraCapture) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
