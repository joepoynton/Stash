# Stash 1.3: Spreadsheet Import and Note Links

**Written 12/11/2026, after reading the codebase at commit `110d84e` (1.2 build 3).**
**Audience: Joe, and the coding model executing each stage. Read "Ground Rules", then your stage, then the parts it references.**

---

## WHY THIS RELEASE EXISTS

The first customer email (Roger, 12/11/2026) raised two things:

1. **"Link to my spreadsheet."** Roger keeps detailed records (e.g. every oil paint he owns) in a spreadsheet. He wants Stash to hold *where* the paints are and link out to the spreadsheet for the detail, rather than duplicating it.
2. **"Import shows a blank iCloud folder."** `SettingsView`'s Import Data uses `.fileImporter(allowedContentTypes: [UTType.json])` and only decodes a Stash JSON export. Everything else is greyed out, so a folder with no `.json` file looks empty. Nothing in the UI says what Import expects. On top of that, export is Pro-only, so most users have no way to produce a file it would accept. He was almost certainly looking for his spreadsheet.

Joe's decisions:
- **Point 1: Part A** (tappable links detected in Notes). No dedicated Link field: that would be a schema change.
- **Point 2: Part B**, a proper spreadsheet import that is **as flexible as possible**: it should cope with the spreadsheet people already have, not demand a format.

---

## GROUND RULES (executor: read first)

All of Part 3 of `docs/stash-next-phase-roadmap.md` applies. The ones that bite here:

1. **No SwiftData schema changes.** Nothing added, removed, renamed or retyped on `Item` or `Location`. Nothing in this spec needs one. If you think it does, STOP and tell Joe.
2. **No CloudKit configuration changes.** `StashModelContainer.swift` is frozen.
3. **iOS 18 APIs only** (deployment target 18.6, SDK is newer: do not use newer APIs).
4. **`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`** project-wide. Parsing and planning run off-main and must be explicitly `nonisolated` (see `ImageCompressor` / `ThumbnailCache` for the pattern).
5. **Reuse the design system:** `SectionHeader`, `StatusBadge`, `Haptics.write()` (once per import, not per item), `LocationPickerSheet` for choosing a destination, `LocationIconView`, semantic colours, light and dark mode, dynamic type.
6. **Tree walks must be cycle-safe:** use `Location+Ancestry.swift` helpers (`ancestorChain`, `pathString`, `ModelContext.unsortedArea(in:)`).
7. **Free tier:** imports never push a free user over `FeatureFlags.freeItemLimit`. Same rule the JSON import already enforces.
8. **No third-party dependencies.** This rules out `.xlsx` reading in this release (see Out of Scope).
9. **CLI simulator builds must be code-signed** (never `CODE_SIGNING_ALLOWED=NO`).
10. **Work on a branch** (`feature/1.3-import-and-links`), not `main`. Commit at the end of each stage with a plain-English message.

---

## PART A: TAPPABLE LINKS IN NOTES

**Goal:** paste a link to a spreadsheet (or anything) into an item's notes, tap to open it.

**Change (ItemDetailSheet only):**
- In the `Section("Notes")`, below the existing `TextField("Add notes…")`, show one row per web link found in `item.notes`.
- Detect with `NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)`. Keep only `http` / `https` schemes. De-duplicate. Maximum 3 rows.
- Each row is a `Link(destination:)` styled as a normal Form row:
  - Icon: `tablecells` when the URL looks like a spreadsheet (host/path contains `icloud.com/numbers`, `docs.google.com/spreadsheets`, `onedrive`, `sharepoint`, `1drv.ms`, or the path ends `.xlsx` / `.xls` / `.csv` / `.numbers`), otherwise `link`. Tinted teal.
  - Title: "Open Spreadsheet" for spreadsheet-looking links, otherwise "Open Link".
  - Secondary text: the host with any leading `www.` removed (e.g. `icloud.com`).
  - Trailing `arrow.up.right` in tertiary label colour.
- Recomputes as the notes change (cheap: notes are short). No row when there are no links.
- The notes field stays exactly as it is: still editable, nothing else changes.
- Footer text on the Notes section, only shown when notes are empty: "Paste a link, e.g. to a spreadsheet, and it becomes tappable."

**Not doing:** links on Locations (they have no notes field, and adding one is a schema change). Link glyphs on list rows. Opening local `file://` paths (they do not survive sync between devices).

**Done when:** pasting an iCloud Numbers share link into notes shows an "Open Spreadsheet" row that opens Numbers; a plain web link shows "Open Link"; two links show two rows; deleting the link removes the row; light and dark mode both clean.

---

## PART B: SPREADSHEET IMPORT

### B1. Entry points and wording (Settings › Data)

Replace the single "Import Data" button with two rows:

- **Import from Spreadsheet…** opens the new import flow (B2 onwards).
- **Restore from Backup…** is the existing JSON import, renamed. Behaviour unchanged.

Section footer: "Spreadsheet import reads CSV files from Numbers, Excel or Google Sheets, or rows you copy and paste. Restore reads a file made with Export Data."

Free-tier gating for both: same as today (blocked only when the user is already at the item limit).

If the user picks a `.json` file inside the spreadsheet flow, detect that it is a Stash export (top-level `areas` key) and hand it to the existing restore path rather than failing.

### B2. Three ways in

The flow is a sheet with its own `NavigationStack`. Start screen offers:

1. **Choose File**: `.fileImporter` with `allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .delimitedText, .plainText, .json]`. Use security-scoped access exactly as `prepareImport(from:)` does.
2. **Paste Rows**: a SwiftUI `PasteButton(payloadType: String.self)` (no iOS paste-permission prompt). Copying a block of cells in Numbers, Excel or Google Sheets puts tab-separated text on the clipboard, so this path needs no file at all. This is the fastest route for most people.
3. **Get Template**: shares a CSV template via the share sheet (see B9).
4. A **"How does this work?"** row opening a short help screen (B9).

(Stage 3 adds a fourth way in: "Open in Stash" from the share sheet / Files.)

### B3. Parser (`SpreadsheetParser.swift`, Foundation only, `nonisolated`)

Input: `Data` (file) or `String` (paste). Output: `[[String]]` rows plus detected delimiter.

- **Encoding:** try UTF-8 (strip BOM), then UTF-16 (Excel "Unicode Text" is UTF-16LE with BOM), then Windows-1252, then Mac Roman. Fail cleanly if none decode.
- **Line endings:** `\n`, `\r\n` and lone `\r` (old Mac Excel).
- **Delimiter detection:** score comma, tab, semicolon (European Excel default) and pipe over the first 20 non-empty lines, ignoring characters inside quotes; pick the one giving the most consistent column count greater than 1. A single-column file is valid (a plain list of item names).
- **Quoting:** RFC 4180: quoted fields may contain delimiters, newlines and doubled quotes (`""`).
- **Trimming:** trim whitespace on every cell. Drop fully blank rows. Pad short rows to the widest row.
- **Limits:** reject files over 5 MB or 10,000 rows with a clear message.

This file and B6's field parsing must import **Foundation only** so they can be exercised from a command-line Swift script against the test files (there is no test target).

### B4. Column mapping (`ImportMapping.swift`)

**Screen 2: "Match your columns".** One row per column: the heading (or "Column A/B/C…"), the first two non-empty sample values in secondary text, and a `Menu` picker for its role.

**Roles:**

| Role | Notes |
|---|---|
| Ignore | Default for anything unrecognised |
| Item name | Exactly one column. Required. |
| Location (full path) | One column like `Studio > Paint cabinet > Drawer 2` |
| Location level 1…5 | Several columns, left to right = outermost to innermost (e.g. Room, Cupboard, Shelf) |
| Quantity | |
| Unit | |
| Minimum | |
| Expiry date | |
| Notes | |
| Link | URL appended to notes on its own line, so Part A makes it tappable |
| Add to notes | Appended to notes as `Heading: value`. This is how extra columns (brand, colour, size) survive without inventing fields. |

"Location (full path)" and "Location level N" are mutually exclusive: choosing one clears the other kind.

**Toggle:** "First row is headings". Auto-detected: on if any first-row cell matches a synonym below, or if row 1 is all non-numeric where row 2 has numbers in the same columns.

**Auto-mapping by heading** (case-insensitive, trimmed, ignore punctuation). First match wins; each role used once except levels and "Add to notes":

- Item name: name, item, item name, thing, description, what, product, title, colour, color (only if nothing else matched name)
- Location (full path): location, path, where, stored, storage location, kept
- Location levels: area, room, space, zone, building, cupboard, cabinet, wardrobe, shelf, drawer, box, bin, container, crate, bag, tub. If two or more of these exist they become levels 1, 2, 3… in column order. If only one exists it becomes level 1.
- Quantity: qty, quantity, count, amount, number, no, stock, how many, on hand
- Unit: unit, units, uom, size unit
- Minimum: min, minimum, min qty, reorder, reorder level, reorder point, par, par level
- Expiry date: expiry, expires, expiry date, exp, best before, bbe, use by, use-by, sell by
- Notes: notes, note, comments, comment, details, info, description (only if not already used as name)
- Link: link, url, web, website, spreadsheet, sheet

If no column maps to Item name and there is exactly one column, that column is the name. Otherwise the user must choose before Continue is enabled ("Choose which column is the item name").

### B5. Locations

**Destination ("Import into")** on the preview screen: **Top level** (default: first path component becomes an Area) or **a chosen space** via `LocationPickerSheet` (every path is created beneath it). This lets Roger import a paint list straight into `Studio > Paint cabinet`.

**Path splitting (full-path column):** split on `>` or `›` if present in any cell of the column; otherwise on ` / ` (with spaces), `\` or `|`. Never split on a bare `/` (it appears in real names: "A4/A3 paper"). Trim each component, drop empty ones.

**Fill down:** toggle "Blank location means same as the row above", default **on**, shown only when a location role is mapped and the column has blanks following non-blanks. Spreadsheets grouped by room routinely leave the location blank on following rows. With level columns, fill down per level, and a non-blank value at level N resets levels below N.

**Matching existing spaces:** walk the existing tree from the destination. At each level, reuse a child whose name matches case-insensitively after trimming (if several siblings match, the oldest by `dateCreated`); otherwise create it. Matching is what makes re-importing or topping up safe. Newly created top-level Areas get the same defaults as creating an Area by hand (check `AddLocationSheet` for icon/colour defaults; do not invent new ones).

**No location:** rows with no location after fill-down go into the destination if one was chosen, otherwise into `ModelContext.unsortedArea(in:)`.

### B6. Field parsing (`ImportFieldParsing.swift`, Foundation only)

- **Quantity:** accepts `3`, `3.0`, `x3`, `3x`, `×3`, `3 tubes`, `3 x 37ml`. Takes the leading integer. Decimals round down (quantity is `Int`). Negative becomes 0. Text after the number (e.g. `tubes`) becomes the unit **only if no Unit column is mapped**, max 20 characters. Unparseable text: quantity stays off and the original text is appended to notes as `Quantity: <text>`. Blank: quantity tracking off.
- **Unit:** max 20 characters (existing rule), truncate.
- **Minimum:** same integer parsing. Only applied when the row also has a quantity; otherwise ignored and counted in warnings.
- **Expiry date:** try, in order: ISO `yyyy-MM-dd`; day-first `d/M/yyyy`, `d-M-yyyy`, `d.M.yyyy`, `d/M/yy`; month-first `M/d/yyyy`; month-year `M/yyyy`, `MMM yyyy`, `MMMM yyyy` (these become the **last day** of that month); `d MMM yyyy`; Excel serial numbers (integers 20000–80000, days since 30/12/1899). **Day-first vs month-first** is decided per column, not per cell: if any value has first part > 12, the column is day-first; if any has second part > 12, month-first; otherwise follow the device locale (UK users get day-first). Show the decision on the preview ("Dates read as day/month/year") with a toggle to flip it. Unparseable dates: no expiry, original text appended to notes as `Expiry: <text>`, counted in warnings.
- **Notes assembly order:** the Notes column first, then each "Add to notes" column as `Heading: value` (skip blanks), then Link URLs, then any `Quantity:` / `Expiry:` fallbacks. Joined with newlines.
- **New item defaults:** match the JSON import: `neverStale = true`, `dateAdded`/`lastVerified` = now, order status normal.

### B7. Preview and confirm (Screen 3)

Built from a plan computed off-main (B8). Nothing is written yet. Shows:

- **Summary:** "Add 46 items in 9 spaces (4 new)". New spaces listed by path.
- **Options:** Import into (destination), Fill down toggle (when relevant), Skip duplicates toggle (default **on**: skips a row whose name matches an existing item in the same space, case-insensitive, or an earlier row in the same file), date order toggle (when there is a date column).
- **Sample:** the first 20 rows as `Path › Item  ×qty unit`, with a "Show all" push for the full list.
- **Warnings** (only those that apply), e.g. "3 rows have no item name and will be skipped", "2 expiry dates couldn't be read; the text is kept in notes", "5 items already exist and will be skipped".
- **Free tier:** if not Pro and the plan exceeds remaining capacity: "Free plan: 18 of 25 items left. 18 will be imported and 28 skipped." with the existing upgrade prompt as a secondary button.
- **Import** button (disabled when nothing would be added). Changing any option recomputes the plan.

### B8. Architecture and write

New folder `Stash/Stash/Import/` (synchronised groups: no pbxproj edits):

- `SpreadsheetParser.swift`: B3. Foundation only.
- `ImportFieldParsing.swift`: B6. Foundation only.
- `ImportMapping.swift`: roles, synonyms, auto-mapping, header detection.
- `ImportPlanner.swift`: `nonisolated`. Takes rows + mapping + options + a **plain-struct snapshot of the existing tree** (names, ids, children, item names per location: built on the main actor before planning) and returns an `ImportPlan` (locations to create, items to add with their target, skips with reasons, warnings, counts). Pure: no SwiftData.
- `ImportWriter.swift`: main actor. Applies an `ImportPlan` to the `ModelContext`: resolves existing locations by id, creates new ones parent-first, inserts items, one `try modelContext.save()`. On failure: `modelContext.rollback()` and show "Nothing was imported" with the error. One `Haptics.write()` on success.
- `SpreadsheetImportView.swift` (+ subviews as needed): the flow.
- `ImportHelpView.swift`, `ImportTemplate.swift`.

Spotlight reindexing happens automatically via the existing `didSave` observer.

**Result:** after success, dismiss the flow and show the same style of alert as today: "Imported 46 items into 9 spaces (4 new). 5 duplicates skipped."

### B9. Template and help

**Template** (`stash-import-template.csv`, written to a temp file and shared, cleaned up on dismiss like the export):

```
Location,Item,Quantity,Unit,Minimum,Expiry,Notes
Kitchen > Cupboard by the oven,Paracetamol,2,boxes,1,31/03/2027,
Garage > Shelf 2,AA batteries,12,,8,,Rechargeable ones are in the drawer
Studio > Paint cabinet > Drawer 1,Oil paints,,,,,https://www.icloud.com/numbers/example
```

**Help screen** (plain, short, no marketing tone):
- Any spreadsheet works. You'll match its columns to Stash on the next screen.
- Only the item name is required. Locations can be one column (`Garage > Shelf 2`) or several (Room, Cupboard, Shelf).
- From Numbers: Share › Export › CSV. From Excel: Export or Save As › CSV. From Google Sheets: File › Download › CSV. Then Choose File.
- Or skip the file: select the cells, copy, come back and tap Paste Rows.
- One sheet at a time. Extra columns can be added to notes.
- You'll see everything before it's added. Matching spaces are reused, not duplicated.

(Executor: verify the menu names above against current Numbers/Excel/Sheets on iOS and adjust wording if they differ. Keep it short.)

### B10. Stage 3: "Open in Stash"

So a CSV can be sent to Stash from Files, Mail or the share sheet:

- Declare document types for `public.comma-separated-values-text`, `public.tab-separated-values-text` and `public.json` with `LSHandlerRank` = `Alternate` (never Owner/Default: Stash must not take over opening CSVs). `LSSupportsOpeningDocumentsInPlace` = NO. Note: Xcode moved Info.plist keys into build settings for this target; document types still go in `Stash/Info.plist` alongside `UIBackgroundModes`. Check the built app's Info.plist afterwards.
- Handle in `ContentView` with `.onOpenURL` (add if absent): for a file URL with a supported extension, present the import flow with the file pre-loaded (JSON → restore confirmation). Respect free-tier gating. Remove the Inbox copy when finished.

---

## STAGES (one Claude Code session each)

**Stage 1: Part A + B1 + parsing and planning logic.**
Part A complete. Settings rows renamed and footer added (Spreadsheet row can open a placeholder for now). `SpreadsheetParser`, `ImportFieldParsing`, `ImportMapping`, `ImportPlanner` written and exercised with a command-line Swift script against every file in `docs/import-test-files/`, printing the plan summary for each so Joe can compare against the expected results table below. Signed simulator build passes.

**Stage 2: The import flow UI.**
Screens (start, columns, preview), file and paste routes, JSON hand-off, template, help, `ImportWriter`, result alert, free-tier handling. Joe tests on device.

**Stage 3: Open in Stash** (B10). Small, separate, because it touches Info.plist.

Then the usual release process (version 1.3, release notes below).

---

## TEST FILES (`docs/import-test-files/`) AND EXPECTED RESULTS

Run each with destination Top level, fill down on, skip duplicates on, into an empty store unless stated.

| File | What it tests | Expected |
|---|---|---|
| `01-simple-path.csv` | One path column, UK dates, units | 6 items. Areas Kitchen, Garage, Bathroom. Paracetamol expiry 31/03/2027. "Plasters" expiry 30/11/2026 from `11/2026`. |
| `02-level-columns.csv` | Room/Cupboard/Shelf columns, blanks meaning "same as above" | 8 items. Fill down puts all Kitchen rows under Kitchen; a new Cupboard value resets Shelf. |
| `03-semicolon-excel.csv` | Semicolon delimiter, UTF-8 BOM, CRLF, `Qty`/`Best before` headings | Delimiter detected as semicolon; heading "Item" maps (no BOM junk); 4 items with quantities. |
| `04-pasted-from-numbers.txt` | Tab-separated, as pasted | Delimiter tab; 5 items; works identically through Paste Rows. |
| `05-messy.csv` | Quoted commas and newlines, blank rows, missing names, `3 tubes`, `x2`, `about a dozen`, bad date, extra Brand column, Link column | 7 items imported, 2 rows skipped (no name). "3 tubes" → 3, unit tubes. "about a dozen" → no quantity, `Quantity: about a dozen` in notes. Bad date → notes `Expiry: soonish`. Brand auto-maps to Ignore; mapping it to Add to notes gives `Brand: …`. Link appended and tappable. Head torch (blank location) fills down into Garage › Shelf 3. Quoted newline in Drill bits' comment survives as a two-line note. |
| `06-names-only.csv` | Single column, no heading | Header toggle off; column is item name; 5 items into Unsorted (or the chosen destination). |
| `07-us-dates.csv` | Month-first dates including 12/31/2027 | Column read as month/day/year; preview says so. |
| `08-oil-paints.csv` | Roger-style list with levels, brand, size, link | Drawer auto-maps to level 1, Colour to item name. Map Brand and Size to Add to notes. Import into Studio › Paint cabinet: 6 items, Drawer 1 and Drawer 2 created beneath it; Brand and Size in notes; link tappable. |
| `01-simple-path.csv` again | Re-import | 0 items added, 6 duplicates skipped, 0 new spaces. |

---

## OUT OF SCOPE (deliberately)

- **Reading `.xlsx` or `.numbers` directly.** Needs a third-party zip/XML library (e.g. CoreXLSX) or Apple's private formats. CSV export and copy-paste cover both apps. Revisit only if users ask.
- Multiple sheets in one go.
- Importing photos.
- Updating existing items from a spreadsheet (import only adds; duplicates are skipped, not merged).
- Saving column mappings for next time.
- A dedicated Link field, or links on Locations (schema changes).
- Fixing the JSON restore's behaviour of duplicating Areas that already exist. Worth a later look; not part of this.

---

## RELEASE NOTES (draft, 1.3)

Bring your existing lists into Stash.

- Import from a spreadsheet: choose a CSV from Numbers, Excel or Google Sheets, or just copy rows and paste them in. Match the columns, check the preview, and Stash builds the spaces for you.
- Links in an item's notes are now tappable, so an item can point to a spreadsheet or web page with the detail.
- "Import Data" is now "Restore from Backup", which says what it actually does.
