//
//  FeatureFlags.swift
//  Stash
//
//  Central feature flag store. All capability checks go here.
//  StoreKit 2 will flip these in a future release — never scatter checks in views.
//

struct FeatureFlags {
    // Placeholder flags for likely premium features (decide at App Store submission).
    static let unlimitedItems = true
    static let iCloudSync = true
    static let photoSupport = true
    static let dataExport = true
}
