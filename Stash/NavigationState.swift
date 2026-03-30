//
//  NavigationState.swift
//  Stash
//
//  Shared navigation state injected at the root and observed by tabs.
//  HomeTab writes selectedTab and browseNavigationPath directly;
//  BrowseTab binds its NavigationStack path to browseNavigationPath.
//

import Foundation
import Observation

@Observable
final class NavigationState {
    var selectedTab: Int = 0
    /// The Browse tab's NavigationStack path. Set to [area] from HomeTab to
    /// deep-link directly into an Area. BrowseTab owns this via @Bindable.
    var browseNavigationPath: [Location] = []
}
