# Stash — Next-Phase Roadmap
**Written 2026-07-04, after a full read of the codebase at commit `67469b1`.**
**Audience: Joe, and any coding model executing a phase later. Each phase is self-contained — read "Ground Rules" plus your phase, and you have everything you need.**

---

## PART 1: HONEST STATE ASSESSMENT

**Verdict: Stash is a mature, structurally sound product. It does not need an ambitious overhaul. It needs one flagship feature, a retention loop, and polish.**

The evidence, from reading every file:

**What is genuinely strong (and unusual for an app at this stage):**
- The data model is small, correct, and deliberately conservative: two models, derived-not-stored low state, CloudKit-safe optionals, no unique constraints. The "same item in multiple places is independent records" decision remains right for this product.
- The write path is disciplined: every mutation goes through model-layer methods on `Item` (`updateQuantity`, `markAsVerified`, `markAsOrdered`, `markAsArrived`, `returnToPlace`, `markAsReplaced`), which is why App Intents were cheap to add and why every future surface (widget, review mode) will be cheap too.
- Data safety is defence-in-depth: cycle-safe ancestry walks, launch-time cycle repair, orphan-item recovery via the "Unsorted" area, iterative cascade delete, local-only container fallback. This is the kind of work that never shows in screenshots and prevents the 1-star reviews.
- The design system (`DesignSystem.swift`) is real, not aspirational: one status-colour source of truth, two header levels, one numeric control, one haptic policy. Screens built months apart read as one surface.
- Friction has already been attacked hard: Quick Add, Save & Add Another, inline ± everywhere, context menus, leading swipes, deep-linkable location paths, per-screen search. The four core use cases (find / check stock / use / restock) each have multiple fast paths.
- Performance work is done where it matters (thumbnail cache, off-main compression, memoized low-stock traversal, O(n) picker tree).

**What is genuinely weak or missing:**
1. **There is no reason to open the app when nothing is wrong.** Stash is a crisis tool today: you open it when you've lost something or run out. An inventory app lives or dies on *trust in the data*, and trust decays silently between crises. Nothing pulls the user back to keep the data honest. This is the one real product-level gap.
2. **The cold-start problem is unsolved for new users.** Suggestion chips are fine, but building a location tree from a blank list is the moment most new users stall. "Map a Space" (already on the backlog) is the correct answer and is the only genuinely ambitious feature this app needs.
3. **The staleness system is dormant.** New items default to `neverStale = true` (a deliberate friction-reduction choice), which means the "Not verified" attention state is effectively opt-in and almost nobody will opt in item-by-item. `lastVerified` is faithfully maintained by every write but nothing celebrates or exercises it. Review Mode turns this dead field into the app's trust engine — without a schema change.
4. **Notifications are a "Coming Soon" placeholder** while the app already tracks expiry dates. Expiry is the one state where the app knowing something and not telling you is a real-world cost (expired medicine, food).
5. **Minor cosmetic drift:** Restock's "Adjust Minimum" swipe is `.blue` (off-system); Restock's empty state is a bare `Text` while every other empty state uses `ContentUnavailableView`; no visual identity beyond teal (the spec itself parked the wordmark).

**What is NOT weak, despite temptation:**
- The architecture does not need restructuring. No MVVM migration, no repository layer, no modularisation. At 7,300 lines with this level of consistency, any "architecture improvement" is churn.
- The data model does not need item-type linking, tags, categories, or barcode scanning. Home inventory items are chargers, tools, and boxes of screws — not retail SKUs. Product linking turns a 10-second Quick Add into a data-entry chore, and the spec's "design for the person who will maintain it" principle cuts the other way here: maintenance must stay cheap.
- iPad split view: skip unless you personally use Stash on iPad. It's real effort for a speculative audience.
- Sharing / multi-user CloudKit: enormous risk (schema + CloudKit config changes, conflict UX) for a personal-inventory product. Do not do this.

**Bottom line:** you asked whether this is "a mature product that needs refinement, or real structural weakness that justifies an ambitious overhaul." It is the former. The Grocery Flow-style transformation is not warranted here — Stash already had its transformation, spread across five disciplined releases. What's left is *finishing the product thesis*, not reinventing it.

---

## PART 2: THE AMBITION (SCOPED HONESTLY)

The version of Stash people evangelise is not a bigger app. It is this sentence:

> **"I photographed my kitchen, and ten minutes later my phone could tell me where anything was — and six months later it still could."**

Two clauses, two problems:

1. **"Ten minutes later"** — population speed. Map a Space makes building the tree tactile and fast, and is the App Store screenshot that sells the app.
2. **"Six months later it still could"** — trust maintenance. The widget keeps Stash present on the home screen; Review Mode makes re-verifying a space a satisfying two-minute ritual instead of an implicit chore; expiry notifications make the app speak up when silence has a cost.

Everything in this roadmap serves one of those two clauses. Anything that serves neither (tags, iPad, sharing, AI item recognition) is ambition for its own sake and is explicitly out.

**Emotional texture goal, stated once so executors understand the register:** Stash should feel like a well-organised garage — calm, exact, quietly satisfying. Every interaction that confirms reality (a verify, a count, a review completed) gets the light haptic and, where natural, a small moment of visual acknowledgement. No gamification, no streaks, no confetti. The reward is the feeling of a true ledger.

---

## PART 3: GROUND RULES FOR EVERY PHASE (executor: read this first)

These apply to all phases. They exist because of real, hard-won gotchas in this project.

1. **No SwiftData schema changes.** Do not add, remove, rename, or retype any property on `Item` or `Location`. If a phase seems to need one, STOP and flag it to Joe — do not improvise with a migration. (No phase below needs one.)
2. **No CloudKit configuration changes.** `StashModelContainer.swift` says "Do not change the schema or CloudKit settings here" — obey it. The container, schema list, and `.automatic` CloudKit setting are frozen.
3. **iOS 18 APIs only.** Deployment target is 18.6. The SDK on this machine is iOS 26.2 — the compiler will happily accept newer APIs; do not use them. Anything iOS 26/27 (including View Annotations) lives on the parked `ios27-siri` branch and is out of scope.
4. **`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`** is set project-wide. All code is MainActor by default. Any off-main work MUST be explicitly `nonisolated` or `Task.detached` (see `ImageCompressor` and `ThumbnailCache` for the canonical patterns).
5. **Reuse the design system — never re-roll:** `StatusColor` (state colours/labels), `SectionHeader` (exactly two levels), `StatusBadge`, `NumericEntryField` (the ONE numeric control), `Haptics.write()` (the ONE haptic, fired on every write action), `AreaPalette`, `CachedThumbnail` (all photo display; call `ThumbnailCache.shared.invalidate(id:)` after any `photo =` assignment), `LocationIconView` (SF Symbol or emoji), `LocationPickerSheet` (all "move to…" flows), `rootAreaColor(for:)` (area tinting).
6. **All model mutations go through `Item`'s methods** (`updateQuantity`, `incrementQuantity`, `decrementQuantity`, `markAsVerified`, `markAsOrdered`, `markAsArrived`, `returnToPlace`, `markAsReplaced`) — never set `quantity`/`lastVerified`/`orderStatusRaw` directly from a view.
7. **Tree walks must be cycle-safe.** Use the helpers in `Location+Ancestry.swift` (`ancestorChain`, `pathString`, `rootAncestor`, `selfAndDescendantIDs`, `ModelContext.cascadeDelete`). Never write a raw `while parent != nil` loop.
8. **File plumbing:** the project uses Xcode 16 synchronized file groups (`objectVersion = 77`) — drop new `.swift` files anywhere under `Stash/Stash/` and they compile; no pbxproj edits needed. Exception: creating a *new target* (Phase 1's widget extension) does require project edits — Joe should create the target in the Xcode UI, then the model fills in the code.
9. **CLI simulator builds MUST be code-signed** — never pass `CODE_SIGNING_ALLOWED=NO` (an unsigned build SIGSEGVs at launch inside a pre-existing `CKContainer.default()` call; it is not your bug). Xcode is at `/Users/joe/Downloads/Xcode.app`, not /Applications.
10. **Free tier:** photos and unlimited-items are Pro (`StoreKitManager.isPro`, `FeatureFlags.freeItemLimit = 25`). Gate at *presentation* (before showing a sheet), with in-form checks as backstops — this is the established pattern. DEBUG builds force `isPro = true`.
11. **Both light and dark mode, dynamic type, semantic colours only.** Test both modes before calling a phase done.

---

## PART 4: THE PHASES

Ordered by value-to-effort. Each is independently shippable. **Do Phase 1 first** — rationale at the end.

---

### PHASE 1 — Home-Screen Widget ("Stash at a glance")

**Goal:** Stash earns a permanent place on the home screen. The widget answers "is anything wrong?" without opening the app, and one tap lands on the thing that's wrong.

**Value: high. Effort: medium. Risk: low-medium (new target).**

**Architecture decision (made now so the executor doesn't improvise a worse one):** the widget does **not** open the SwiftData store. Moving the store into an App Group container to share it would be a risky data migration for zero user-visible gain. Instead, the app writes a small JSON snapshot to an App Group container on every save, and the widget renders the snapshot. The widget is a *display* of last-known state, not a second reader of the database.

**One-time setup (Joe, in Xcode UI — not the model):**
- Add a Widget Extension target named `StashWidget` (deployment target 18.6, Swift, no Live Activity).
- Create App Group `group.Poynt.Stash` in the developer portal and add the App Groups entitlement to BOTH the app target and the widget target. *(This is an entitlement addition — it is not a CloudKit or schema change, but it is flagged here because it touches signing.)*

**Specific changes:**

1. **New file `Stash/Stash/Attention.swift` (shared logic extraction):** move the `AttentionReason` enum and the needs-attention computation out of `HomeTab.swift` (where both are currently `private`) into a shared, non-private home:
   - `enum AttentionReason` exactly as it exists today (outOfPlace / lowStock / expired / expiringSoon / notVerified, with `rank`, `label`, `color` via `StatusColor`).
   - `func attentionEntries(items: [Item], staleThresholdDays: Int, now: Date = Date()) -> [(item: Item, reason: AttentionReason)]` — the exact logic currently in `HomeTab.needsAttentionItems` (same precedence order, same 30-day expiry window, same `neverStale` exemption, same severity-then-name sort).
   - Refactor `HomeTab` to call it. Behaviour must be identical — this is a move, not a redesign.
2. **New file `Stash/Stash/WidgetSnapshot.swift`:** a `@MainActor enum WidgetSnapshotWriter` with `static func write(context: ModelContext)`:
   - Fetches all items, computes attention entries via `Attention.swift`, and encodes a `Codable` snapshot struct: `generatedAt: Date`, `totalItems: Int`, `attentionCount: Int`, `restockCount: Int` (items where `manuallyRestocking` or below minimum — mirror `RestockTab.restockItems`), and `topAttention: [SnapshotRow]` (max 4: item UUID string, name, reason label, reason colour name as a string key, location `pathString`).
   - Writes JSON to `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.Poynt.Stash")!.appendingPathComponent("widget-snapshot.json")` (atomic write).
   - Calls `WidgetCenter.shared.reloadAllTimelines()` after writing.
   - Trigger: observe `ModelContext.didSave` with a 1-second debounce — copy the exact observer/debounce pattern from `SpotlightIndexer.startObserving()`/`scheduleReindex()`; add a `WidgetSnapshotWriter.start()` call next to `SpotlightIndexer.start()` in `StashApp`. Also write once at launch.
3. **Widget target code (`StashWidget/`):** a `TimelineProvider` that reads and decodes the JSON (placeholder content if missing), one entry, `.policy: .never` (reloads are pushed by the app). Two families:
   - **systemSmall:** app icon glyph + either "All good" with total item count, or a prominent attention count ("3 need attention") tinted orange, plus restock count line. `widgetURL(URL(string: "stash://attention"))`.
   - **systemMedium:** header row ("Stash · 214 items"), then up to 4 attention rows: name, reason as a small coloured badge (map the colour key string back to a `Color` — reproduce the `StatusColor` colour values in the widget target; do not import app files that pull in SwiftData), each row a `Link` to `stash://item/<uuid>`. Empty state: "Everything in its place." in secondary style.
   - Respect light/dark via semantic colours. No photos in v1 of the widget.
4. **Deep-link handling in the app:**
   - Add to `NavigationState`: `var pendingOpenItemID: UUID? = nil` and `var pendingShowAttention: Bool = false` (transient UI state — not a schema change).
   - In `ContentView`, add `.onOpenURL { url in ... }`: `stash://item/<uuid>` → set `pendingOpenItemID` and `selectedTab = 0`; `stash://attention` → set `pendingShowAttention = true`, `selectedTab = 0`.
   - In `HomeTab`, consume via `.onChange(of: navState.pendingOpenItemID)` + `.onAppear`: look the item up in `allItems`, set `selectedItem`, clear the flag. `pendingShowAttention` → set `showAllAttention = true`, clear the flag.
   - Register the `stash` URL scheme in the app target's Info settings (CFBundleURLTypes).

**Constraints:** all Ground Rules. The widget target must not import any file that imports SwiftData. Widget deployment target 18.6. No CloudKit in the widget.

**Risks:**
- *Stale widget after a sync on another device:* the snapshot only updates when this device's app saves. Acceptable for v1; note "as of <time>" is deliberately NOT shown (it reads as brokenness) — the `.never` policy plus app-driven reloads is the honest contract.
- *Target setup friction:* pbxproj edits for new targets are error-prone for a model — hence Joe creates the target in Xcode first.
- *App Group misconfiguration* shows up as a nil container URL — guard and log rather than crash.

**Done when:** add an item, put it below minimum → within ~2 seconds the widget shows it; tap the row → app opens with that item's detail sheet presented; delete the item → widget updates; widget renders correctly in light/dark and with no snapshot file present; app runs unchanged with the widget never installed.

---

### PHASE 2 — Review Mode ("walk the shelves")

**Goal:** turn data maintenance from an implicit chore into a fast, deliberately satisfying ritual: pick a space, sweep through its items one at a time, confirm reality. This activates the dormant `lastVerified` machinery and is the feature that makes the app still trustworthy six months in.

**Value: high (this is the product thesis). Effort: medium. Risk: low (pure UI over existing write methods).**

**Specific changes:**

1. **New file `Stash/Stash/ReviewSessionView.swift`** — a full-screen cover (not a sheet; this is a mode) presented from a location:
   - Input: a `Location` and a `Bool includeNested`. Item set: `location.itemList`, plus all descendant items when `includeNested` (walk with a visited-set or reuse `selfAndDescendantIDs` to gather locations, then their items). Order: by location (`pathString`), then name.
   - **One item per screen, card style:** large photo via `CachedThumbnail` (3:2, placeholder if none), item name (`.title2.bold()`), location `pathString` in secondary (matters when nested), notes if present, current quantity as a read-only line when tracked.
   - **Action row (fixed at bottom, big targets):**
     - **"Still here"** (primary, teal, checkmark icon) → `item.markAsVerified()`, `Haptics.write()`, auto-advance.
     - **"Update count"** (only when quantity tracked) → expands an inline `NumericEntryField` pre-set to current quantity + a confirm button → `item.updateQuantity(to:)`, advance.
     - **"Moved…"** → `LocationPickerSheet` (same wiring as ItemDetailSheet's move: set `item.location`, `item.lastVerified = Date()`), advance.
     - **"Gone"** (destructive) → confirm alert ("Delete \"name\"? This cannot be undone.") → `modelContext.delete(item)`, advance.
     - **Skip** (quiet text button) → advance without writing.
   - Progress: "4 of 17" + a thin linear progress bar tinted with `rootAreaColor(for: location) ?? .teal`. An X in the toolbar exits anytime (writes already made are kept — that's correct and needs no warning).
   - Each confirm gets a brief visual acknowledgement (e.g. a 0.25s checkmark overlay transition) before advancing — the "true ledger" moment. Keep it subtle; no sounds, no confetti.
   - **Summary screen at the end:** "Review complete — Kitchen" with counts: confirmed / updated / moved / removed / skipped, and a Done button. Use `SectionHeader` styling conventions.
   - Empty input (no items) → skip straight to a "Nothing to review here" state with Done.
2. **Entry points:**
   - `BrowseLocationView` add-menu sibling: new toolbar menu item "Review this Space" (`checkmark.seal`) — shown only when the space (or its descendants) has items; opens a small pre-flight dialog only when the space has child spaces: "Include nested spaces?" (Yes / Just this space).
   - Location context menu in `BrowseLocationView.locationRows`: add "Review" alongside Move/Edit/Delete.
   - **Home nudge:** in `HomeTab`, a single quiet row (below Needs Attention, above Your Spaces; `SectionHeader` level `.secondary`, title "Time for a review") shown when some root Area's *oldest* item `lastVerified` (ignore `neverStale` here — review is about physical reality, not the attention list) is older than `2 × staleThresholdDays` days. Show the single most-overdue Area: "Garage — last fully reviewed 4 months ago" with a "Review" button that launches the session (nested included). Cap: one row, never a list. If the user starts or completes any review of that area, the row recomputes away naturally (no stored state).
3. **No schema change:** location "review freshness" is *derived* (oldest descendant `lastVerified`), never stored.

**Constraints:** all Ground Rules. All writes via existing `Item` methods only. `Haptics.write()` on every write action. Review must never mutate `neverStale` (verifying a `neverStale` item is fine — it just updates `lastVerified`).

**Risks:**
- *Deriving area freshness walks every item* — same cost class as `needsAttentionItems`, computed once per Home render over an in-memory array; fine at this inventory scale. Do not add caching preemptively.
- *Deleting items mid-iteration:* snapshot the item list (array of PersistentIdentifiers or the items themselves) at session start; guard each card against the item having been deleted elsewhere.
- *Scope creep magnet:* no scheduling, no reminders, no per-room streaks. If it's not in this description, it's out.

**Done when:** reviewing a 10-item space touches all five actions correctly (verify updates `lastVerified`, count update routes through `updateQuantity`, move relocates, gone deletes after confirm, skip writes nothing); summary counts are accurate; exiting mid-session keeps completed writes; the Home nudge appears for a stale area and disappears after review; light/dark clean.

---

### PHASE 3 — Expiry & Attention Notifications (replace "Coming Soon")

**Goal:** the app speaks up when silence has a real-world cost. Local notifications for expiring items — nothing else in v1 of this feature.

**Value: medium-high. Effort: low-medium. Risk: low.**

**Specific changes:**

1. **New file `Stash/Stash/ExpiryNotifications.swift`** — `@MainActor enum ExpiryNotifications`:
   - `static func requestAuthorization() async -> Bool` (UNUserNotificationCenter, `.alert, .sound, .badge`).
   - `static func reschedule(items: [Item], warningDays: Int)`: remove all pending requests with the app's identifier prefix (`expiry-<uuid>`), then for each item with a future `expiryDate`, schedule ONE notification at 9:00 AM local time `warningDays` before expiry (if that moment is already past but expiry is still future, schedule for 9:00 AM tomorrow). Title: "Expiring soon"; body: "\(name) expires \(date formatted .abbreviated) — \(pathString)". `userInfo: ["itemID": uuid]`. **Cap at the 60 soonest** (iOS limit is 64 pending).
   - Trigger: the same debounced `ModelContext.didSave` observer pattern (third consumer of it — copy from `SpotlightIndexer`, start alongside it in `StashApp`), plus a reschedule when the setting changes.
2. **Settings:** replace the "Coming Soon" row with: a "Expiry alerts" toggle (`@AppStorage("expiryNotificationsEnabled")`, default off; turning on runs the auth request — if denied, flip the toggle back and show an alert pointing to system Settings), and, when on, a stepper "Warn \(n) days before" (`@AppStorage("expiryWarningDays")`, default 30, range 7–90).
3. **Tap-through:** implement `UNUserNotificationCenterDelegate` in a small `NotificationDelegate` (set in `StashApp.init`); on response, read `itemID` and route through the same `NavigationState.pendingOpenItemID` mechanism built in Phase 1. *(If Phase 1 hasn't shipped, build that small `NavigationState` + `HomeTab` consumption piece here — it's ~20 lines and both phases list it so whichever ships first carries it.)*
4. **Consistency note:** the Needs Attention list uses a fixed 30-day expiring-soon window today. When `expiryWarningDays` exists, update `Attention.swift`/`HomeTab` to use it so the app and its notifications agree.

**Constraints:** all Ground Rules. Local notifications only — no push, no server. Default OFF; never prompt for permission before the user flips the toggle.

**Risks:** permission-denied UX (handled above); duplicate notifications if identifiers aren't stable (use `expiry-<uuid>`, remove-then-add); the 64-pending cap (handled).

**Done when:** with alerts on and an item expiring in `warningDays`, a notification is pending (verifiable via `UNUserNotificationCenter.current().pendingNotificationRequests`); changing the item's expiry or deleting it reschedules; tapping the notification opens the item's detail sheet; toggle-off removes all pending expiry notifications.

---

### PHASE 4 — Batch Operations ("select things, act once")

**Goal:** heavy-maintenance moments (reorganising a shelf, purging a box) stop being one-item-at-a-time.

**Value: medium. Effort: medium. Risk: medium (gesture/edit-mode interplay).**

**Specific changes (all within `BrowseLocationView` + one small new file):**

1. **"Select Items" mode:** new entry in the sort/add toolbar area (menu item "Select Items", shown when the space has ≥ 2 items). Enters a selection state (`@State private var selectingItems = false`, `@State private var selectedItemIDs: Set<UUID> = []`).
   - In selection mode, item rows render a leading circle/checkmark (custom overlay on `ItemRow` — do NOT try to combine SwiftUI List selection with the existing Button rows), tapping toggles membership; swipe actions, context menus, and the row's detail-tap are disabled while selecting; spaces rows are dimmed and inert (items only).
   - Toolbar swaps to: "Done" (exits, clears) and a count ("3 selected").
   - **Bottom action bar** (safeAreaInset, material background), buttons disabled at zero selection: **Move…** (one `LocationPickerSheet`; on select, loop `item.location = loc; item.lastVerified = Date()`), **Verify** (loop `markAsVerified()`), **Restock** (loop `manuallyRestocking = true` for tracked items), **Delete** (one confirm alert naming the count, then loop delete). One `Haptics.write()` per batch action, not per item.
2. **"Verify All Here" one-tap:** separate add-menu item (no selection mode needed) — confirm dialog "Mark all \(n) items in \(name) as verified?" → loop `markAsVerified()`. This is the 80% case and must stay one tap + one confirm.
3. Extract the bottom bar into `BatchActionBar.swift` if `BrowseLocationView` gets unwieldy (it's already the biggest file — prefer extraction).

**Constraints:** all Ground Rules. Selection state is per-screen and transient (resets on navigation). Reorder mode (`editMode`) and selection mode are mutually exclusive — hide each's entry point while the other is active.

**Risks:** `BrowseLocationView` complexity (mitigate by extracting); accidental batch deletes (single confirm with explicit count is required); free-tier — none of these actions create items, so no gating.

**Done when:** select 3 items → move relocates all with `lastVerified` bumped; batch delete confirms with count and removes; Verify All updates every item; reorder mode and select mode can't be entered simultaneously; leaving the screen exits selection.

---

### PHASE 5 — Map a Space (the flagship)

**Goal:** the blank-canvas killer and the App Store centrepiece. Walk a room, photograph each cupboard/shelf/box; every photo becomes a child space with the photo attached; name them all on one grid; done. Physical reality first, labels second.

**Value: high (for new users / marketing; lower for Joe's own populated inventory — which is exactly why it isn't first). Effort: high (the most new UI + camera lifecycle work). Risk: medium.**

**Specific changes:**

1. **New file `Stash/Stash/MultiCaptureCameraController.swift`:** a UIKit controller modelled directly on `AVCameraViewController` (same session setup, RotationCoordinator pattern, KVO token retained as an instance property — copy that pattern exactly, it was a hard-won orientation fix) with these differences:
   - Does NOT dismiss after capture. Shutter → capture → compress immediately via `ImageCompressor.compress(_:)` (off-main; append the resulting ~100–300KB `Data` to an array — never retain full-res captures) → thumbnail appears in a horizontal strip along the bottom (small UIImageViews from the compressed data; tap a thumbnail to delete that capture with a confirm).
   - A capture counter ("4 spaces") and a prominent "Done (4)" button; X cancels the whole flow (confirm if captures exist: "Discard 4 photos?").
   - Cap captures at 20 per session (alert at cap) — memory ceiling ~6MB compressed, fine.
2. **New file `Stash/Stash/MapSpaceView.swift`:** SwiftUI wrapper + the naming step:
   - Presents the camera full-screen; on Done, shows the **naming grid**: a 2-column grid of 3:2 photo cards, each with a `TextField` underneath pre-filled `"New space 1"`, `"New space 2"`, …; first field auto-focused; return advances focus to the next field. A per-card delete (X) removes a capture. Toolbar: Cancel (confirm, discards everything — nothing is written before Confirm) and **"Create 4 Spaces"**.
   - Confirm: for each remaining capture, create `Location(name: trimmedName-or-default, parent: currentLocation)` with `location.photo = data`, insert. Root-level captures (from onboarding, below) get `parent: nil` and become Areas. Then dismiss to the space, which now lists the new children.
3. **Entry points:**
   - `BrowseLocationView` add-menu: "Map this Space" (`camera.viewfinder`), directly under "Add Space".
   - `HomeTab` onboarding empty state: secondary CTA under the chips — "Or map a space with your camera" (creates Areas at root).
   - **Pro gating:** photos are Pro. Free tier sees the entry points with the established `lock.fill` treatment → `UpgradePromptSheet(message: "Unlock Stash Pro to map your spaces with photos.")`. Gate at presentation, per the pattern.
4. No Spotlight/intents work needed — `SpotlightIndexer`'s didSave observer picks up the new locations automatically.

**Constraints:** all Ground Rules. Camera permission denial → the same "enable in Settings" treatment as `AVCameraViewController.showPermissionDenied`. Locations are exempt from the free item cap (only *items* are capped) — but the whole feature is Pro anyway. Nothing is inserted into the model context until Confirm.

**Risks:** camera session lifecycle across the capture→naming transition (stop the session when leaving the camera screen); memory (compress-on-capture handles it); the naming grid keyboard dance (focus chaining) is fiddly — test on device, not just simulator; users mapping the same room twice creates duplicate spaces — acceptable, they can delete.

**Done when:** from an empty "Kitchen", capture 5 photos, rename 3, delete 1 at naming, confirm → 4 child spaces exist with photos and names, thumbnails render in Browse rows via `CachedThumbnail`, Area/photo displays are correct; Cancel at every stage writes nothing; free tier hits the upgrade sheet; orientation is correct for photos taken in landscape.

---

### PHASE 6 — Texture & Identity Pass (small, last, optional)

**Goal:** sand the remaining seams. Explicitly cosmetic; do opportunistically or skip until App Store marketing matters.

**Specific changes (complete list — do not expand it):**
1. Restock "Adjust Minimum" swipe tint: `.blue` → `.teal` (design-system compliance).
2. Restock empty state: replace the bare `Text("Nothing to restock.")` with a `ContentUnavailableView { Label("Nothing to Restock", systemImage: "cart") } description: { Text("Items below their minimum will appear here.") }` — matching Browse's pattern.
3. Route Restock's "Mark as Ordered"/"Mark as Arrived" swipe tints through `StatusColor.onOrder.color` instead of literal `.teal` (no visual change; one source of truth).
4. Area cards: add a subtle press-down scale effect (`.scaleEffect` on a custom ButtonStyle, ~0.97, spring) — the grid currently feels inert on tap.
5. App icon: produce 2–3 alternate concepts (the archivebox glyph is serviceable; a wordmark exploration belongs in App Store listing work, per the original spec's parking note). This is a design task, not a code task — flag for Joe.
6. Re-verify dark mode + Dynamic Type on any screen the earlier phases touched.

**Constraints/Risks:** none beyond Ground Rules. **Done when:** the six items above are done and nothing else changed.

---

## PART 5: ORDERING RATIONALE & WHAT TO DO FIRST

| # | Phase | Value | Effort | Ship independently? |
|---|-------|-------|--------|---------------------|
| 1 | Widget | High | Medium | Yes |
| 2 | Review Mode | High | Medium | Yes |
| 3 | Expiry notifications | Med-high | Low-med | Yes |
| 4 | Batch operations | Medium | Medium | Yes |
| 5 | Map a Space | High* | High | Yes |
| 6 | Texture pass | Low-med | Low | Yes |

*High for acquisition/new users; low for already-populated inventories.

**Do the widget (Phase 1) first.** Reasons: (a) it's the highest daily-visible return per unit of risk — every glance at the home screen re-engages the trust loop; (b) it builds the deep-link plumbing (`pendingOpenItemID`) that Phase 3 also needs; (c) it's the only phase with target/entitlement setup, so getting it done early surfaces any signing friction while the codebase is otherwise quiet; (d) Review Mode (the thesis feature) lands better when the widget is already reminding you something needs attention.

Map a Space is deliberately *not* first despite being the flagship: your own inventory is already populated, so you can't dogfood it daily the way you can dogfood the widget and Review Mode — and it's the biggest, riskiest build. Do it when 1–3 have shipped and the retention loop is real; it then becomes the marketing release.

---

## PART 6: LEAVE ALONE (explicit no-touch list)

A later, eager model must treat these as load-bearing and finished. Refinement of these is not on any phase; a "cleanup" of them is a regression risk with no upside.

- **`Item.swift` / `Location.swift` data model** — no new stored properties, no reworking of the derived `.low` status, no item-type linking, no tags. The standalone-records decision is final.
- **`StashModelContainer.swift`** — schema list, CloudKit `.automatic`, local-only fallback. The file says do not change it. Don't.
- **`Location+Ancestry.swift`** — the cycle-safe walks, `repairCycles`, `cascadeDelete`, `unsortedArea`. This is the data-safety layer; extend by calling it, never by rewriting it.
- **`ThumbnailCache.swift` / `ImageCompressor.swift`** — the concurrency design (MainActor default + detached decode, `@unchecked Sendable` transfer box, generation-based invalidation) is deliberate and correct. Don't "simplify" it.
- **`StoreKitManager.swift`** — including the `Transaction.updates` lifetime listener and the UserDefaults-backed fallback. Purchase code is done.
- **The `Intents/` folder** — entities, queries, the three intents, `SpotlightIndexer`. Working and verified. The richer Siri work lives on the `ios27-siri` branch and stays there until the new SDK; do not merge or reimplement pieces of it on main.
- **Navigation architecture** — `NavigationState` as the cross-tab deep-link spine, Browse's single `NavigationStack` path, sheet-per-tab presentation. Phases 1/3 *add* two transient fields; nothing restructures it.
- **The three-tab structure** — Home / Browse / Restock, Settings behind the gear. No fourth tab, ever (the widget and review mode do not become tabs).
- **`QuickAddSheet` and the add flows** — just fixed and tuned in the last release (insert-then-relate ordering comment in `saveAndClear` is load-bearing). Leave the verified-by-default (`neverStale = true`) choice alone — Review Mode is the answer to staleness, not reverting that default.
- **Delete/confirm flows** — the two-step cascade confirms, "move contents to parent/Unsorted" recovery paths. Exactly as specced, safety-critical.
- **`DesignSystem.swift`** — extend by *using* it; never fork a second header style, numeric control, or haptic pattern.
- **Free-tier gating placement** — gate-at-presentation with in-form backstops. Don't consolidate or "DRY" it into something clever.

---

*End of roadmap. Companion to `stash-build-spec.md` (v1.0 spec, historical). When executing a phase, quote Ground Rules + your phase to the executing model verbatim.*
