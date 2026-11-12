# Stash 1.3

Build: 4. Minimum iOS: 18.6.

## Release notes

Bring your existing lists into Stash.

- Import from a spreadsheet: choose a CSV from Numbers, Excel or Google Sheets, or just copy rows and paste them in. Match the columns, check the preview, and Stash builds the spaces for you.
- Send a CSV to Stash from Files, Mail or the share sheet and the import opens with the file ready.
- Links in an item's notes are now tappable, so an item can point to a spreadsheet or web page with the detail.
- "Import Data" is now "Restore from Backup", which says what it actually does.

## Verified so far (12/11/2026)

- Signed Debug simulator builds pass. 123 import checks pass (scripts/import-check/run.sh).
- Checked in the iPhone 18 Pro Max simulator: file import with the oil-paints test file, import destination picker, Excel file explanation, Stash backup handed to restore, opening a CSV and a backup from outside the app.
- No SwiftData or CloudKit changes. Info.plist gains document types (CSV, TSV, JSON) at Alternate rank with open-in-place off; UIBackgroundModes unchanged.

## Not yet checked (on Joe's iPhone)

- Paste Rows from Numbers, Get Template share sheet, dark mode on the import screens.
- Real share sheet "Open in Stash", and the Inbox copy being removed.
- Free-plan limit during an import, opening a file while Settings is showing.
- Numbers, Excel and Google Sheets export menu names in the in-app help.

## Next action

Merge feature/1.3-import-and-links, test on device, then archive, upload to TestFlight and submit.
