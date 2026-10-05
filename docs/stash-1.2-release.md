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
- Upload to App Store Connect succeeded. Apple processing is pending; internal group Joe - Internal Testing contains only Joe.
- Archive and IPA retained locally in ignored build/releases/1.2-3/.
- Existing listing wording and ten screenshots retained in the App Store Connect 1.2 draft. Manual release selected.

## Remaining before submission

Install the TestFlight build and check Pro/free-tier behaviour, light/dark appearance and larger text. Finish Add/Return batch entry, Add detail, remembered/fixed locations and picker cancellation checks. Verify normal iCloud behaviour with the distribution build. Submit to App Review only after Joe approves.
