# Stash — Complete Build Specification
**Version 1.0 — For use with Claude Code**
**Stack: SwiftUI + SwiftData, iOS 17+, CloudKit sync**

---

## HOW TO USE THIS DOCUMENT

This spec is structured in build phases. Work through one phase at a time. Each phase is independently testable before moving on. Do not attempt to build everything at once.

At the start of each Claude Code session, paste this document and state which phase you are working on. This is your single source of truth. If Claude Code makes a decision not covered here, stop and refer back.

---

## PART 1: WHAT THE APP IS

Stash is a personal inventory app. The core promise is: "I always know where something is and how much I have." Think of it as a video game inventory for real life — a tree of storage spaces, with items living inside them.

The primary user is detail-oriented and will genuinely maintain the app. Design for that person. Do not soften the experience to accommodate casual users who won't maintain data.

**The four use cases, in priority order:**
1. Find where something is
2. Check the stock level of something
3. Update quantity after using something
4. Know what needs buying

---

## PART 2: DATA MODEL

This is the foundation. Get this right before building any UI.

### Location (self-referential)

```swift
@Model
class Location {
    var id: UUID
    var name: String
    var icon: String?          // SF Symbol name. Root nodes only. Optional.
    var photo: Data?           // Compressed image data. Max 1200px long edge.
    var color: String?         // Hex string. Optional per-area tint. Root nodes only.
    var parent: Location?      // Nil = root node (Area)
    var children: [Location]   // Child locations
    var items: [Item]          // Items stored here
    var dateCreated: Date
    var isStarred: Bool        // Field reserved for v1.1 UI. Always false in v1.
}
```

**Rules:**
- Root nodes (parent == nil) are called "Areas" and appear as cards on the Home screen grid
- Any node at any depth can hold items
- Depth is unlimited
- Locations can be moved (parent reassigned), taking all children and items with them
- When a root node is demoted (given a parent), retain its icon and color in the data — do not delete. The fields simply stop being displayed.

**Deletion behaviour:**
When deleting a Location that contains items or child Locations, present an action sheet with three options:
- "Delete everything inside" (cascade delete all children and items)
- "Move contents to [parent name]" (orphan children and items up one level to the deleted node's parent, or to root if no parent)
- "Cancel"

Never silently delete. Always confirm destructive actions.

### Item

```swift
@Model
class Item {
    var id: UUID
    var name: String
    var notes: String?
    var photo: Data?              // Compressed image data. Max 1200px long edge.
    var quantity: Int?            // Nil = quantity tracking off
    var unit: String?             // Optional label: "ml", "tablets", "rolls", etc.
    var minimumQuantity: Int?     // Only meaningful when quantity != nil
    var expiryDate: Date?
    var orderStatus: OrderStatus  // Enum: .normal, .low, .onOrder
    var dateAdded: Date
    var lastVerified: Date        // Updated on any write action (not on view)
    var isStarred: Bool           // Reserved for v1.1. Always false in v1.
    var location: Location        // Required. Every item must belong to a location.
}

enum OrderStatus {
    case normal
    case low        // Derived: quantity != nil && quantity < minimumQuantity
    case onOrder    // User-set via Restock tab
}
```

**Rules:**
- The same item type (e.g. paracetamol) can exist as completely independent records in multiple locations. There is no item type linking. Each record is standalone.
- `orderStatus` of `.low` is derived, not stored — compute it, don't save it as a field
- `lastVerified` updates on any write (quantity change, field edit, move). Does NOT update on view.
- `quantity` is always an integer. No decimals.
- `unit` is free text, max 20 characters. Displayed next to quantity number. If nil, just the number shows.

---

## PART 3: VISUAL DESIGN SYSTEM

Apply this consistently from day one. Retrofitting is painful.

### Colour

- **Primary accent: SwiftUI `.teal`** — used for buttons, interactive elements, badges, the low-stock indicator dot, and highlights
- **Per-area optional tint:** Root Location nodes can have an optional `color` (hex string). This tint is applied subtly — as a light background wash on the Area card, and as a tinted navigation bar tint when browsing inside that area. It does not replace teal; it complements it.
- Use semantic colours throughout (`Color(.label)`, `Color(.systemBackground)`, etc.) — never hardcode light/dark values. This ensures dark mode works without extra effort.

### Dark Mode

Support both light and dark mode from day one. Use semantic SwiftUI colours exclusively. Test both modes before considering any phase complete.

### Typography

Follow iOS dynamic type. Do not hardcode font sizes. Use `.title`, `.headline`, `.body`, `.caption` etc. This gives accessibility for free.

### Accent application

| Element | Treatment |
|---|---|
| Buttons (primary) | Teal fill |
| Buttons (secondary) | Teal label, clear background |
| Low stock dot | Teal (or area tint if set) |
| Badges | Teal |
| On order indicator | System orange |
| Expiry warning | System orange |
| Destructive actions | System red |
| Starred items | System yellow star |

### Photos

- **Compression:** Scale down on save to max 1200px on the long edge. Store as `Data` in SwiftData.
- **Area cards:** 3:2 landscape crop. Photo fills the card background with a dark overlay (40% opacity black) for text legibility.
- **Browse row thumbnails:** Square crop, 44×44pt. Left-aligned on row.
- **Item detail view:** Full-width display, 3:2 landscape crop.
- **Never show photos in search results rows.** Photos appear in cards, thumbnails, and detail views only.

### Grid layout

- **iPhone:** 2-column adaptive grid for Area cards
- **iPad (future):** 3–4 columns via SwiftUI `LazyVGrid` with adaptive columns. Use `GridItem(.adaptive(minimum: 160))` so it scales automatically.

---

## PART 4: APP STRUCTURE

Three tabs. No more.

```
TabView
├── Home (house.fill)
├── Browse (square.grid.2x2.fill)
└── Restock (cart.fill)
```

Settings is accessed via a gear icon in the navigation bar of the Home tab. It is not a fourth tab.

---

## PART 5: SCREEN SPECIFICATIONS

### 5.1 HOME TAB

**Purpose:** Dashboard. Quick answers. Not a navigation hub.

**Layout (top to bottom):**

1. **Navigation bar:** Title "Stash". Gear icon (trailing) opens Settings.

2. **Search bar:** Prominent, below nav bar. Activates live search across all items, location names, and notes. See Section 5.4 for full search spec.

3. **Needs Attention section** (shown only when items exist in this state):
   - Header: "Needs Attention"
   - Shows items that are: below minimum quantity (and not on order), expiring within 30 days, or not verified in 90+ days (configurable in Settings)
   - Each row: item name, reason tag ("Low stock" / "Expires soon" / "Not verified"), location path in secondary text
   - Tap row: opens item detail sheet
   - If nothing needs attention: section hidden entirely (not an empty state message)

4. **Recently Accessed section:**
   - Header: "Recently Accessed"
   - Auto-tracked on view. Maximum 8 items. Deduplicate: same item viewed within 10 minutes counts once.
   - Each row: item name, location path in secondary text, quantity if tracked
   - Tap row: opens item detail sheet

5. **Your Spaces section:**
   - Header: "Your Spaces"
   - Adaptive grid of Area cards (root Location nodes)
   - Each card: photo background (if set) with dark overlay, or solid tinted background with icon centred. Name at bottom. Low-stock dot (small filled circle, bottom-right) if any descendant item is below minimum quantity.
   - Tap card: navigates into Browse tab at that Area's level

**Empty state (no Areas created yet):** Show onboarding prompt. See Section 5.6.

---

### 5.2 BROWSE TAB

**Purpose:** Navigating and organising the full tree. Adding and editing locations and items.

**Navigation:** Standard iOS navigation stack. Each level is its own screen. Back button returns one level.

**Breadcrumb:** Display as a subtitle line beneath the navigation bar title at each level. Format: `Garage › Top Shelf › Blue Box`. Each segment in the breadcrumb is tappable and navigates directly to that ancestor level.

**Each Browse screen shows two types of row:**

**Location row (container — tap to drill deeper):**
- Left: SF Symbol icon or square photo thumbnail (44×44pt)
- Centre: Location name (primary). Child count and item count in secondary text (e.g. "2 shelves · 4 items")
- Right: chevron.right + optional low-stock dot (small teal or area-tinted filled circle)
- Tap: navigate into that location
- Swipe left: Edit, Delete

**Item row (leaf — tap for detail):**
- Left: square photo thumbnail if exists, otherwise a plain square placeholder
- Centre: Item name (primary). Location path not shown (you're already in the location). Notes preview in secondary text if notes exist.
- Right: if quantity tracked — current quantity + unit label + inline minus/plus buttons. If not tracked — nothing on right.
- Tap: opens Item Detail Sheet (modal)
- Swipe left: Edit, Delete

**Distinguishing locations from items:** Different row styles as above. If a screen contains both locations and items, show locations first under a "Spaces" header, items under an "Items" header. Do not mix them in one unsectioned list.

**Add button:** "+" in navigation bar trailing position. Reveals action sheet: "Add Space" or "Add Item".

**Inline quantity buttons (+/-):** 
- Shown only on items with quantity tracking enabled
- Minus button disabled (greyed) when quantity is 0
- Tapping either immediately updates the record and updates `lastVerified`
- No confirmation required for quantity changes

---

### 5.3 RESTOCK TAB

**Purpose:** Act on low stock. Manage shopping and receiving.

**Content:** All items where `quantity < minimumQuantity`, regardless of location.

**Grouping:** Group by Area (root ancestor). Each group has a header with the Area name and icon.

**Item row in Restock:**
- Item name
- Location path in secondary text
- Current quantity / minimum quantity shown (e.g. "2 / 5 tablets")
- Status indicator: orange "Low" label for normal low state, teal "On Order" label with shippingbox icon for on-order state

**Interactions:**
- Swipe right on a row: "Mark as Ordered" — changes `orderStatus` to `.onOrder`, mutes the low-stock visual, item stays in list
- Swipe right on an on-order row: "Mark as Arrived" — presents a stepper sheet: "How many arrived?" — user inputs number, quantity increments by that amount, `lastVerified` updates, `orderStatus` resets to `.normal`. Item leaves the list if now at or above minimum.
- Swipe left: "Adjust Minimum" — opens a small sheet to edit `minimumQuantity`

**Partial receipt:** The arrival stepper handles this naturally. User enters the number that arrived. If still below minimum after update, item stays in Restock.

**On-order item that is still below minimum:** Show the "On Order" state and mute the low-stock indicator. Do not show both simultaneously.

**Empty state:** Single centred message: "Nothing to restock." No further elaboration.

---

### 5.4 SEARCH

**Trigger:** Search bar on Home tab. Tapping activates a full-screen search experience.

**Behaviour:**
- Live search as the user types. No submit button.
- Enable iOS keyboard autocomplete (the inline completion arrow). This is standard behaviour — ensure the search field does not suppress it.
- Search scope: item names, location names, notes fields. All three.
- Results update with each keystroke.

**Result row:**
- Item name (primary, large)
- Location path in secondary text below (e.g. `Garage › Top Shelf`)
- Quantity + unit on the right if tracked
- Inline +/- buttons if quantity tracked (identical to Browse row)
- No photo thumbnail in search results

**Tapping a result row:** Opens Item Detail Sheet (modal). Does not navigate into the Browse tree.

**No results state:** "No results for '[query]'" — clean, centred.

---

### 5.5 ITEM DETAIL SHEET

**Presentation:** Modal sheet (`.sheet` modifier). Swipe down to dismiss.

**Content:**
- Item name (large, editable inline on tap)
- Photo (3:2, full width if set). Camera icon to add/replace. Tapping photo opens fullscreen view.
- Location path (tappable — navigates to that location in Browse when dismissed)
- Notes (editable inline)
- If quantity tracked: current quantity with +/- buttons, unit label, minimum quantity
- Expiry date (if set): shown prominently with colour indicator (orange if within 30 days)
- Last verified: shown as relative time ("Verified 3 days ago"). "Mark as Verified" button below — one tap, updates `lastVerified`, no modal.
- Date added
- Order status (if `.onOrder`): banner at top: "On its way"
- Delete button (destructive, bottom of sheet)

**Editing:** Fields edit inline. No separate "Edit mode." Changes save automatically.

---

### 5.6 LOCATION DETAIL / EDIT SHEET

**Triggered by:** Tapping Edit on a location row swipe action, or tapping a location name in breadcrumb.

**Content:**
- Name (editable)
- Icon picker (SF Symbol grid — root nodes only)
- Colour picker (optional tint — root nodes only). Show a palette of 8 curated colours plus "None."
- Photo (add/replace/remove)
- Move location: "Move to..." picker — shows full location tree, allows selecting new parent or root
- Delete button (destructive)

---

### 5.7 ADD ITEM FLOW

**Trigger:** "Add Item" from Browse tab "+" action sheet.

**Fields presented:**
1. Name (required, auto-focused)
2. Notes (optional)
3. Track quantity toggle (off by default)
   - If on: quantity stepper + unit text field + minimum quantity stepper
4. Expiry date (optional date picker)
5. Photo prompt: "Add a photo?" with camera and library options. Skip link clearly visible. This is encouraged but never required.

**Save:** Saves item to the current Browse location. Updates `dateAdded` and `lastVerified` to now.

---

### 5.8 ADD LOCATION FLOW

**Trigger:** "Add Space" from Browse tab "+" action sheet.

**Fields:**
1. Name (required, auto-focused)
2. If adding at root level: Icon picker (SF Symbol) + optional colour tint
3. Photo prompt: "Add a photo of this space?" — more prominently encouraged than for items. Camera and library options. Skip link present.

**Save:** Creates Location as child of current Browse level (or as root if at top level).

---

### 5.9 SETTINGS SCREEN

**Access:** Gear icon in Home tab navigation bar.

**Rows:**

| Setting | Detail |
|---|---|
| Stale record threshold | Slider or stepper. Default: 90 days. Range: 30–365 days. Items not verified in this many days appear in Needs Attention. |
| Expiry warning window | Default: 30 days. Range: 7–90 days. (Placeholder in v1, functional in v1.1) |
| Export data | Exports full inventory as JSON. Share sheet. Format described in Section 7. |
| About | App name, version number, build number. |

**Notification preferences row:** Present as a placeholder row labelled "Notifications — Coming Soon" in v1. Do not wire up.

---

### 5.10 ONBOARDING / EMPTY STATE

**First launch (no Areas):**

Do not show a tutorial or walkthrough. Instead, show the Home screen with a single prominent prompt:

> **"Start by adding your spaces"**
> *Where do you keep things? Garage, loft, car — add them here.*

Below this: a row of tappable suggestion chips: common Area names (Garage, Loft, Car, Kitchen, Bedroom, Office, Work, Shed). Tapping one creates that Area instantly with a sensible default SF Symbol. User can rename or delete after.

A manual "+" button is also present to add a custom Area.

**Empty Area (has location, no items):**

Single centred CTA button: "+ Add your first item"

**Goal:** Get the user to a state where the app contains real data as fast as possible. Every empty state should offer the next action, not an explanation.

---

## PART 6: NAVIGATION FLOWS

### Moving an item

In Item Detail Sheet: "Move to..." option opens a location picker (full tree). User selects destination. Item's `location` relationship updates. `lastVerified` updates.

### Moving a location

In Location Detail Sheet: "Move to..." opens location picker (excluding self and own descendants to prevent circular references). Selecting new parent updates `parent` relationship. All children and items move with it automatically (they reference their immediate parent, not the full path).

### Deleting a non-empty location

Present action sheet:
- "Delete '[name]' and everything inside" — cascade delete
- "Move contents to [parent name]" — items and children go up one level
- "Cancel"

Confirmation required for destructive option: "Are you sure? This cannot be undone." — presented as a second alert.

### Breadcrumb navigation

Tapping any segment in the breadcrumb navigates directly to that ancestor. Implemented by popping the navigation stack to the appropriate depth.

---

## PART 7: DATA EXPORT FORMAT

JSON export from Settings. Human-readable field names. Export the full tree.

```json
{
  "exportDate": "2025-03-28T10:00:00Z",
  "appVersion": "1.0",
  "areas": [
    {
      "id": "uuid",
      "name": "Garage",
      "icon": "car.fill",
      "color": "#2A9D8F",
      "children": [
        {
          "id": "uuid",
          "name": "Top Shelf",
          "children": [],
          "items": [
            {
              "id": "uuid",
              "name": "WD-40",
              "notes": "Large can",
              "quantity": 2,
              "unit": "cans",
              "minimumQuantity": 1,
              "expiryDate": null,
              "orderStatus": "normal",
              "dateAdded": "2024-11-01T09:00:00Z",
              "lastVerified": "2025-03-01T14:00:00Z"
            }
          ]
        }
      ],
      "items": []
    }
  ]
}
```

Photos are excluded from export (binary data, file size). Note this clearly in the export share sheet: "Photos are not included in the export."

---

## PART 8: PHOTO HANDLING

### Compression

On save (camera capture or library selection), scale the image down so that the long edge is no greater than 1200px. Maintain aspect ratio. Save as JPEG at 0.8 quality. Store the resulting `Data` directly in SwiftData.

### Storage note

Not every item will have a photo. Photos are most useful for locations (to aid spatial memory) and occasionally for items where visual identification matters (e.g. "which HDMI cable is this?"). The compression settings above should keep individual photos to 100–300kb. For a typical inventory of ~200 items with ~30% having photos, total storage will be well under 20MB.

### Display

- Area card: fill card background, 3:2 crop, 40% black overlay for text legibility
- Browse row: 44×44pt square thumbnail, left-aligned
- Item detail: full-width 3:2 display
- Search results: no photo displayed

---

## PART 9: ICLOUD / CLOUDKIT SYNC

Enable CloudKit sync via SwiftData's ModelContainer configuration from day one.

```swift
let schema = Schema([Location.self, Item.self])
let config = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
let container = try ModelContainer(for: schema, configurations: [config])
```

**CloudKit requirements for the data model:**
- All relationships must be optional in CloudKit-compatible SwiftData models. Ensure the data model handles this.
- No `@Attribute(.unique)` constraints — CloudKit does not support them. Use UUID for identification instead.
- Sync conflicts: SwiftData/CloudKit uses last-write-wins. This is acceptable for a single-user app.

**User-facing sync indication:** No explicit sync indicator in v1. CloudKit syncs silently. If sync fails (no iCloud account), the app functions offline and syncs when available. No error state needed in v1.

---

## PART 10: LOW STOCK BUBBLING

The low-stock dot on an Area card indicates that at least one descendant item (at any depth) is below its minimum quantity and is NOT in `.onOrder` status.

**Implementation:** Compute this as a derived property on Location:

```swift
var hasLowStockDescendant: Bool {
    // Check direct items
    let hasLowItem = items.contains { item in
        guard let qty = item.quantity, let min = item.minimumQuantity else { return false }
        return qty < min && item.orderStatus != .onOrder
    }
    // Recurse into children
    return hasLowItem || children.contains { $0.hasLowStockDescendant }
}
```

**Visual treatment:** Small filled circle (8pt diameter), positioned bottom-right of the Area card. Teal colour, or the area's tint colour if set. No number. No border. Subtle — not a badge.

---

## PART 11: SIRI / APPINTENTS (FUTURE — ARCHITECTURE NOTE)

Do not build Siri integration in v1. However, ensure the core write operations (update quantity, mark as verified, mark as ordered) are implemented as methods on the model layer — not embedded in view code. This makes wrapping them in AppIntent in v1.5 straightforward.

---

## PART 12: IPAD / SPLIT VIEW (FUTURE — ARCHITECTURE NOTE)

v1 is iPhone-first. v1.5 will introduce iPad split-view layout (Browse tree on left panel, detail on right).

To make this retrofit easier:
- Use `NavigationSplitView` instead of `NavigationStack` where practical, with a fallback column for iPhone. SwiftUI handles the collapse automatically.
- Keep detail views (Item Detail Sheet, Location Detail) as standalone views that can be presented either as sheets or in a split-view column.

---

## PART 13: FREEMIUM ARCHITECTURE NOTE

Do not build paywall logic in v1. However:
- Keep all feature flags as simple booleans in a central `FeatureFlags` struct
- Do not scatter capability checks throughout views
- This allows StoreKit 2 to flip these flags cleanly in a future release

Likely premium features (decide at App Store submission, not now): unlimited items, iCloud sync, photo support, data export.

---

## PART 14: BUILD PHASES

Work through these in order. Do not start Phase 2 until Phase 1 is tested and stable.

---

### PHASE 1 — Foundation (Data + Sync)

**Goal:** Data model and CloudKit sync working. No UI beyond a bare scaffold.

**Tasks:**
1. Create Xcode project: SwiftUI, SwiftData, iOS 17 minimum deployment
2. Implement `Location` and `Item` models exactly as specified in Part 2
3. Configure CloudKit-enabled ModelContainer (Part 9)
4. Verify models compile and basic CRUD operations work in previews
5. Confirm CloudKit entitlements are set and iCloud capability is enabled

**Test:** Can you create a Location, create an Item inside it, move the item to a different Location, and delete the Location with cascade? All in Swift previews or a simple test view.

---

### PHASE 2 — Browse Tab

**Goal:** Full tree navigation, add/edit/delete locations and items.

**Tasks:**
1. Build Browse tab with navigation stack
2. Implement location rows and item rows with correct visual distinction
3. Implement breadcrumb subtitle with tappable segments
4. Implement "Add Space" and "Add Item" flows
5. Implement inline quantity +/- buttons on item rows
6. Implement swipe actions (Edit, Delete) on both row types
7. Implement deletion action sheet for non-empty locations (Part 6)
8. Implement Location Detail Sheet (move, edit, delete)
9. Implement Item Detail Sheet (all fields, mark as verified)

**Test:** Can you build a tree three levels deep, add items at various levels, move a location and confirm its children moved with it, delete a non-empty location and confirm the action sheet appears?

---

### PHASE 3 — Home Tab

**Goal:** Dashboard with Needs Attention, Recently Accessed, and Area grid.

**Tasks:**
1. Build Area card grid (adaptive columns, photo background or icon)
2. Implement `hasLowStockDescendant` computed property and low-stock dot on cards
3. Build Needs Attention section (low stock, expiry within 30 days, stale records)
4. Build Recently Accessed section (view-tracked, max 8, 10-minute dedup window)
5. Tapping Area card navigates into Browse at that Area's level

**Test:** Create items in various states (low stock, expiring soon, old lastVerified) and confirm they surface correctly. Confirm recently accessed updates on view.

---

### PHASE 4 — Search

**Goal:** Live search across items, locations, and notes. Working from Home tab search bar.

**Tasks:**
1. Implement search bar on Home tab
2. Implement live search query across names, location names, notes
3. Build search result rows (item name, location path, quantity, inline +/-)
4. Tap result opens Item Detail Sheet
5. Enable autocomplete

**Test:** Search for a term that appears in a name, a location name, and a notes field. Confirm all three surface. Confirm +/- works from search results.

---

### PHASE 5 — Restock Tab

**Goal:** Full restock list with order/arrival flow.

**Tasks:**
1. Build Restock list grouped by Area
2. Implement "Mark as Ordered" swipe action
3. Implement "Mark as Arrived" stepper sheet
4. Implement "Adjust Minimum" swipe action
5. Empty state

**Test:** Create items below minimum, confirm they appear. Mark one as ordered, confirm visual state change. Mark as arrived with a partial quantity, confirm item stays if still below minimum.

---

### PHASE 6 — Photos

**Goal:** Photo capture, compression, and display throughout the app.

**Tasks:**
1. Implement photo picker/camera integration on Location and Item
2. Implement compression on save (1200px long edge, JPEG 0.8)
3. Implement Area card photo backgrounds (3:2 crop, dark overlay)
4. Implement Browse row thumbnails (44×44pt square)
5. Implement Item Detail full-width photo display
6. Photo prompt on Add Location flow (encouraged)
7. Camera icon in Item Detail (discoverable, not prompted on creation)

**Test:** Add photos to an Area and an Item. Confirm compression is applied. Confirm display at all three sizes. Confirm no photos appear in search results.

---

### PHASE 7 — Visual Polish

**Goal:** Full design system applied. Dark mode. Area tints. Onboarding.

**Tasks:**
1. Apply teal accent colour consistently throughout
2. Implement per-area colour tint (card background wash + navigation tint)
3. Implement colour picker in Add/Edit Location (8 curated colours + none)
4. Verify dark mode throughout — every screen
5. Build onboarding empty state with suggestion chips
6. Review all empty states (Restock, Needs Attention, Recently Accessed, Browse)
7. Verify adaptive type throughout (no hardcoded font sizes)

**Test:** Toggle dark mode. Check every screen. Add an area colour and confirm it tints correctly without clashing with teal interactive elements.

---

### PHASE 8 — Settings + Export

**Goal:** Settings screen complete. JSON export working.

**Tasks:**
1. Build Settings screen (gear icon in Home nav bar)
2. Implement stale record threshold (default 90 days, adjustable)
3. Implement JSON export (Part 7 schema) via share sheet
4. About row with version and build number
5. Notification preferences placeholder row

**Test:** Change stale threshold and confirm Needs Attention section responds. Export data and verify JSON matches schema. Confirm photos are excluded and the share sheet notes this.

---

## APPENDIX A — SF Symbol Suggestions

| Context | Symbol |
|---|---|
| Default Area icon | `archivebox.fill` |
| Garage | `car.fill` |
| Loft / Storage | `shippingbox.fill` |
| Kitchen | `fork.knife` |
| Bedroom | `bed.double.fill` |
| Car | `car.circle.fill` |
| Work | `briefcase.fill` |
| Garden | `leaf.fill` |
| Office | `desktopcomputer` |
| On Order indicator | `shippingbox` |
| Verified | `checkmark.circle.fill` |
| Low stock | `exclamationmark.circle.fill` |
| Starred | `star.fill` |

---

## APPENDIX B — Decisions NOT Made Yet (Future Versions)

- Push notifications (v1.1)
- Configurable expiry warning window (v1.1)
- Starred items UI (v1.1)
- CSV / spreadsheet import (v1.1) — see import notes below
- iPad split-view layout (v1.5)
- Siri / AppIntents integration (v1.5)
- Freemium / StoreKit 2 paywall (pre-App Store submission)
- Widget support (future)

**Note on spreadsheet import (v1.1):**
Joe's existing Excel inventory has a 3-column structure across ~8 sheets: location › item › contents. This was built without Stash's tree structure in mind, so automated import will be imperfect. The realistic approach for v1.1 is a guided CSV import where the user exports one sheet at a time, maps columns to Stash fields (location path, item name, notes), and the importer creates the location tree and items accordingly. A fully automated Excel import is not realistic — the data will need some manual cleanup regardless. The JSON export format (Part 7) is the clean path for future migrations once the data lives in Stash.

---

## APPENDIX C — Deferred Design Decisions (Add in Phase 7 Polish)

**Area colour tinting cascades through child levels**
When a root Area has a colour tint assigned, that tint should apply at every child level within that area — not just on the Area card itself. Specifically: the navigation bar tint and the breadcrumb text colour should reflect the Area's colour as the user drills deeper. This gives the user a persistent peripheral cue about which top-level space they are inside. Confirmed needed after Phase 3 testing — the breadcrumb currently shows in default teal regardless of Area colour. Implement during Phase 7 visual polish.

The colour tinting approach needs further thought. Three options identified:
- Tint the Area card name text in the assigned colour (visible on the photo card)
- Apply a low-opacity colour overlay on top of the Area card photo
- Apply the colour to child-level folder icons and navigation elements, even if not visible on the photo card itself
Preferred approach: apply the area colour to child location row icons (the folder/container icons in Browse rows), the navigation bar tint at all child levels, and the breadcrumb segments. The photo card itself gets the area name in white (standard) — the colour identity becomes apparent as soon as the user drills in.

**Recently Accessed — reduce prominence on Home screen**
The Recently Accessed section works correctly but may be too prominent on the Home screen relative to its usefulness. Consider reducing its visual weight in Phase 7 — smaller row height, less vertical space, or moving it below Needs Attention with a more compact layout. Do not remove it — the feature is useful, just potentially overweighted in the current layout.

**Delete swipe action must be red throughout Browse**
Currently inconsistent — delete is teal at some levels and red at others. Delete must always be system red (`.destructive`) at every level of the Browse tree. Edit swipe action should be teal. Fix in Phase 7 or as a standalone bug fix.

**Area card photo crop must be constrained to 3:2**
All Area cards must display at a consistent 3:2 landscape ratio regardless of the source photo dimensions. Currently photos from the library can produce wildly different card heights. Use `.aspectRatio(3/2, contentMode: .fill)` with `.clipped()` on the card image. Fix as a standalone bug fix — do not wait for Phase 7.

**App name / logo treatment**
The "Stash" text in the navigation bar is currently plain system text. A future version should replace this with a stylised logo or wordmark. No design concept exists yet — park this for post-v1 once a visual identity is established. Consider as part of App Store listing design work.

---

## APPENDIX D — Future UX Improvements (Post v1)

**Rapid item entry ("quick add") mode**
A frictionless way to populate a location quickly without navigating into each item's detail. The proposed interaction: within a Browse location, a "Quick Add" button opens a minimal input where the user types a name and hits return/enter — the item is created instantly with no other fields, and the cursor returns to the input field ready for the next item. The user can then tap into any of the created items afterwards to fill in quantity, notes, expiry etc. Goal is to make bulk population of a new space (e.g. unpacking a box) as fast as possible. Consider for v1.1.

---

*End of Stash Build Specification v1.0*
