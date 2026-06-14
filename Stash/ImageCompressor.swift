//
//  ImageCompressor.swift
//  Stash
//
//  Scales an image so its longest edge is ≤ 1200px, then encodes as JPEG at 0.8 quality.
//

import UIKit

enum ImageCompressor {
    /// Decodes and compresses photo `data` entirely off the main thread, then
    /// returns the compressed JPEG. The previous call sites wrapped this in a
    /// `Task {}` that inherited the view's MainActor context — so the work ran
    /// on the main thread and hitched the dismiss animation (P2). The detached
    /// task here guarantees the heavy decode/scale/encode runs in the
    /// background; callers hop back to main only to assign the result.
    nonisolated static func compress(_ data: Data) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            guard let image = UIImage(data: data) else { return nil }
            return compress(image)
        }.value
    }

    nonisolated static func compress(_ image: UIImage) -> Data? {
        let maxDimension: CGFloat = 1200
        let size = image.size
        let longestEdge = max(size.width, size.height)

        let scaled: UIImage
        if longestEdge > maxDimension {
            let ratio = maxDimension / longestEdge
            let newSize = CGSize(
                width:  (size.width  * ratio).rounded(),
                height: (size.height * ratio).rounded()
            )
            let renderer = UIGraphicsImageRenderer(size: newSize)
            scaled = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        } else {
            scaled = image
        }

        return scaled.jpegData(compressionQuality: 0.8)
    }
}
