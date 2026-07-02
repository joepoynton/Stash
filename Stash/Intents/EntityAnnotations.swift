//
//  EntityAnnotations.swift
//  Stash
//
//  The iOS 27 View Annotations seam.
//
//  WWDC 2026's View Annotations API maps on-screen views to App Entities so
//  Siri can resolve conversational references — "move THIS to the loft" while
//  an item's detail sheet is open, "what's low in HERE" while browsing a
//  space. These two modifiers are already applied at every screen that shows
//  a single entity (ItemDetailSheet) or a location's contents
//  (BrowseLocationView, incl. each row), so the annotation points are chosen,
//  wired, and shipping today as no-ops.
//
//  WHY A NO-OP AND NOT AN #available BRANCH: this project currently builds
//  with the iOS 26.2 SDK. `if #available(iOS 27, *)` is only a *runtime*
//  check — the annotation symbols themselves don't exist in the 26.2 SDK, so
//  referencing them anywhere in compiled code (even inside an availability
//  branch) cannot compile until the iOS 27 SDK is installed. Isolating the
//  call sites behind these two modifiers makes activation a change to THIS
//  FILE ONLY, with the runtime availability guard exactly as below.
//
//  ACTIVATION (once building with the iOS 27 SDK) — replace each `self` with
//  the guarded annotation, using whatever the final API spelling is, e.g.:
//
//      if #available(iOS 27, *) {
//          // Entity is created lazily here, never on iOS 18 paths.
//          self.appEntityContext(ItemEntity(item: item))
//      } else {
//          self
//      }
//
//  Everything else in the App Intents layer is already correct for the
//  annotated case: MoveItemIntent handles "move this…", UseItemIntent
//  handles "I've used two of these", and both re-resolve live objects in
//  perform(), so a reference resolved from the screen behaves identically
//  to one resolved by voice.
//

import SwiftUI

extension View {

    /// Marks this view as showing `item`, so conversational references to it
    /// ("this", "these") resolve to its ItemEntity. No-op until the app is
    /// built with the iOS 27 SDK — see the activation note above.
    ///
    /// Takes the live model (not an entity): entity snapshots load photo data,
    /// and nothing should pay that cost per-row on OS versions where the
    /// annotation can't exist.
    @ViewBuilder
    func stashItemContext(_ item: Item) -> some View {
        self
    }

    /// Marks this view as showing `location` and its contents, so references
    /// like "in here" resolve to its LocationEntity. No-op until built with
    /// the iOS 27 SDK — see the activation note above.
    @ViewBuilder
    func stashLocationContext(_ location: Location) -> some View {
        self
    }
}
