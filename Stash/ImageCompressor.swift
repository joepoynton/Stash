//
//  ImageCompressor.swift
//  Stash
//
//  Scales an image so its longest edge is ≤ 1200px, then encodes as JPEG at 0.8 quality.
//

import UIKit

enum ImageCompressor {
    static func compress(_ image: UIImage) -> Data? {
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
