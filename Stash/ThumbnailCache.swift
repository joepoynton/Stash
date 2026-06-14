//
//  ThumbnailCache.swift
//  Stash
//
//  P1 — the most important performance fix. Item and location rows used to
//  call UIImage(data:) on the full ~1200px stored JPEG on every render, each
//  one also faulting the externally-stored photo blob off disk. With a long
//  inventory that's a stutter on every scroll.
//
//  CachedThumbnail decodes once, off the main thread, downscaled to the size
//  actually shown, and keeps the result in an in-memory NSCache keyed by the
//  model's UUID. On a cache hit nothing touches the stored Data at all — the
//  expensive external-storage fault simply never happens again. The same cache
//  serves item rows, location rows, and Area cards (at card resolution).
//

import SwiftUI
import UIKit
import Observation

// MARK: - Sendable transfer box

/// A decoded thumbnail is finished and immutable by the time we hand it back
/// to the main actor, so transferring it across the actor boundary is safe.
/// UIImage isn't Sendable, so we wrap it to say so explicitly.
private struct SendableImage: @unchecked Sendable {
    let image: UIImage
}

// MARK: - Cache

@Observable
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    /// Bumped on every invalidation. CachedThumbnail observes this so a row
    /// that's still on screen (e.g. behind the detail sheet where the photo
    /// was just replaced) refreshes instead of showing the old thumbnail.
    private(set) var generation: Int = 0

    private let cache = NSCache<NSString, UIImage>()

    /// NSCache can't enumerate its keys, so we track which size-keys exist per
    /// id in order to evict every resolution of an image on invalidation.
    private var keysByID: [UUID: Set<String>] = [:]

    private init() {
        cache.countLimit = 300
    }

    func image(for id: UUID, pixelSize: CGSize) -> UIImage? {
        cache.object(forKey: key(id, pixelSize) as NSString)
    }

    func store(_ image: UIImage, for id: UUID, pixelSize: CGSize) {
        let k = key(id, pixelSize)
        cache.setObject(image, forKey: k as NSString)
        keysByID[id, default: []].insert(k)
    }

    /// Call whenever an item's or location's photo is replaced or removed.
    func invalidate(id: UUID) {
        for k in keysByID[id] ?? [] {
            cache.removeObject(forKey: k as NSString)
        }
        keysByID[id] = nil
        generation &+= 1
    }

    private func key(_ id: UUID, _ size: CGSize) -> String {
        "\(id.uuidString)|\(Int(size.width))x\(Int(size.height))"
    }
}

// MARK: - CachedThumbnail view

struct CachedThumbnail<Content: View, Placeholder: View>: View {
    let id: UUID
    /// Display size in points. Multiplied by the display scale for the decode
    /// resolution and cache key.
    let size: CGSize
    /// Reads the stored photo Data. Called only on a cache miss, so the
    /// external-storage fault never happens on a hit or on every render.
    let dataProvider: () -> Data?
    @ViewBuilder var content: (Image) -> Content
    @ViewBuilder var placeholder: () -> Placeholder

    @Environment(\.displayScale) private var displayScale
    @State private var uiImage: UIImage?

    var body: some View {
        Group {
            if let uiImage {
                content(Image(uiImage: uiImage))
            } else {
                placeholder()
            }
        }
        .task(id: ReloadKey(id: id, generation: ThumbnailCache.shared.generation)) {
            await load()
        }
    }

    private var pixelSize: CGSize {
        CGSize(width: size.width * displayScale, height: size.height * displayScale)
    }

    private func load() async {
        let target = pixelSize
        if let cached = ThumbnailCache.shared.image(for: id, pixelSize: target) {
            uiImage = cached
            return
        }
        // Cache miss: read the stored photo on the main actor (SwiftData models
        // are main-actor bound), then decode + downscale off the main thread.
        guard let data = dataProvider() else {
            uiImage = nil
            return
        }
        let decoded = await Task.detached(priority: .userInitiated) { () -> SendableImage? in
            guard let thumb = UIImage(data: data)?.preparingThumbnail(of: target) else { return nil }
            return SendableImage(image: thumb)
        }.value
        guard let decoded else {
            uiImage = nil
            return
        }
        ThumbnailCache.shared.store(decoded.image, for: id, pixelSize: target)
        uiImage = decoded.image
    }
}

private struct ReloadKey: Equatable {
    let id: UUID
    let generation: Int
}
