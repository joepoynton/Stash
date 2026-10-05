# Stash 1.2

Build: 3. Minimum iOS: 18.6.

## Release notes

Adding and moving possessions is now easier.

- Add an item with just its name and leave its location in Unsorted until later.
- Quick Add now has a visible Add button, and Done saves a typed item before closing.
- Move items directly from Browse and search, with a searchable location picker and clearer Select buttons.
- Tap a Restock row to open Item Detail.

## Verified on 05/10/2026

- Signed Debug simulator builds passed.
- Isolated SwiftData checks passed: moving preserves unrelated fields and updates inverse relationships; duplicate location names have distinct full paths; name-only capture reuses Unsorted and survives save/refetch.
- Joe checked moves, separate expand/Select controls, Quick Add saving through Done, Restock detail and swipe actions, and persistence after relaunch on his iPhone 17 Pro Max.
- Signed Release archive and App Store export passed. Exported app is version 1.2 build 3 with distribution signing, production push entitlement and the existing Production CloudKit container iCloud.Poynt.Stash.
- Camera/photo permission text and remote-notification background mode are present in the built app. Xcode moved permission/orientation settings from Info.plist into project settings.
- Upload to App Store Connect succeeded. Apple processing completed with VALID status; build 1.2 (3) is IN_BETA_TESTING, and internal group Joe - Internal Testing contains only Joe, whose invitation state is INVITED.
- Archive and IPA retained locally in ignored build/releases/1.2-3/.
- Existing listing wording and ten screenshots retained in the App Store Connect 1.2 draft. Manual release selected; build 3 attached. Joe confirmed the TestFlight build works and authorised submission. Submitted on 05/10/2026 at 12:07 BST; Apple confirmed WAITING_FOR_REVIEW, with MANUAL release retained.

## Next action

Wait for Apple's review result. If approved, ask Joe before manually releasing version 1.2. If Apple requests changes, inspect its feedback before editing or resubmitting.
