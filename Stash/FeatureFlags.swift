//
//  FeatureFlags.swift
//  Stash
//
//  Central feature flag store. All capability checks go here.
//  Driven by StoreKitManager.isPro — never scatter checks in views directly.
//  Access via StoreKitManager.featureFlags computed property.
//

struct FeatureFlags {
    let isPro: Bool

    /// Unlimited items (free tier capped at freeItemLimit).
    var unlimitedItems: Bool { isPro }

    /// Camera and photo library access on items and locations.
    var photoSupport: Bool { isPro }

    /// JSON data export.
    var dataExport: Bool { isPro }

    /// iCloud sync — always enabled.
    var iCloudSync: Bool { true }

    /// Maximum items allowed on the free tier.
    static let freeItemLimit = 25
}
