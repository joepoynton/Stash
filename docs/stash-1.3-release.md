# Stash 1.3

Build: 4. Minimum iOS: 18.6.

## Release notes

Bring your existing lists into Stash.

- Import from a spreadsheet: choose a CSV from Numbers, Excel or Google Sheets, or just copy rows and paste them in. Match the columns, check the preview, and Stash builds the spaces for you.
- Send a CSV to Stash from Files, Mail or the share sheet and the import opens with the file ready.
- Links in an item's notes are now tappable, so an item can point to a spreadsheet or web page with the detail.
- "Import Data" is now "Restore from Backup", which says what it actually does.

## Verified (12/11/2026)

- Signed Debug simulator builds pass. 126 import checks pass (scripts/import-check/run.sh).
- Simulator (iPhone 18 Pro Max): file import with the oil-paints test file, import destination picker, Excel file explanation, Stash backup handed to restore, opening a CSV and a backup from outside the app.
- Joe's iPhone (debug build): Paste Rows from Numbers, Open in Stash from Numbers' share sheet (Stash is under More until iOS learns it), duplicate detection on a re-import ("6 items already exist"), tappable links (Open Link and Open Spreadsheet), Get Template share sheet, dark mode on the import screens.
- Numbers export path confirmed as the three-dots button, Export, CSV. Excel and Google Sheets wording in the help is general, not checked.
- No SwiftData or CloudKit changes. Info.plist gains document types (CSV, TSV, JSON) at Alternate rank with open-in-place off; UIBackgroundModes unchanged.
- Signed Release archive and App Store export passed. Exported app is version 1.3 build 4 with Apple Distribution signing, production push and the Production CloudKit environment (iCloud.Poynt.Stash).
- Apple's updated Developer Program License Agreement was accepted by Joe first (it blocked the export until then).
- Uploaded to App Store Connect from Xcode Organizer on 12/11/2026. Archive and IPA kept in ignored build/releases/1.3-4/.

## Not yet checked

- Free-plan limit during an import (debug builds force Pro, so this needs the TestFlight build).
- Inbox copy being removed after Open in Stash; opening a file while Settings is showing.

## Next action

Wait for Apple to finish processing build 4, install it from TestFlight on Joe's iPhone and check the free-plan limit, then create the 1.3 version in App Store Connect (release notes above, build 4 attached, manual release) and submit.
