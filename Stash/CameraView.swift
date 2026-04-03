//
//  CameraView.swift
//  Stash

import SwiftUI

struct CameraView: UIViewControllerRepresentable {
    let onImageCaptured: (Data) -> Void

    func makeUIViewController(context: Context) -> AVCameraViewController {
        let vc = AVCameraViewController()
        vc.onPhotoCaptured = onImageCaptured
        return vc
    }

    func updateUIViewController(_ uiViewController: AVCameraViewController, context: Context) {}
}
