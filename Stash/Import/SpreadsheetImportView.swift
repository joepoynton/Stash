//
//  SpreadsheetImportView.swift
//  Stash
//
//  1.3 spreadsheet import flow, opened from Settings › Data.
//
//  PLACEHOLDER (1.3 stage 1). Stage 2 replaces the body with the real flow:
//  start screen (Choose File / Paste Rows / Get Template / help), "Match your
//  columns", then the preview built from ImportPlanner. The parsing and
//  planning it will sit on are already in this folder.
//

import SwiftUI

struct SpreadsheetImportView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Not Ready Yet",
                systemImage: "tablecells",
                description: Text("Spreadsheet import is still being built. It will read CSV files from Numbers, Excel or Google Sheets, or rows you copy and paste.")
            )
            .navigationTitle("Import from Spreadsheet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
