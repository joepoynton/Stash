//
//  ImportColumnsView.swift
//  Stash
//
//  1.3 spreadsheet import (spec B4). "Match your columns": what each column
//  of the spreadsheet means to Stash.
//

import SwiftUI

struct ImportColumnsView: View {
    var model: SpreadsheetImportModel
    var onContinue: () -> Void

    var body: some View {
        List {
            Section {
                Toggle("First row is headings", isOn: Binding(
                    get: { model.mapping.hasHeaderRow },
                    set: { model.setHasHeaderRow($0) }
                ))
            }

            Section {
                ForEach(model.columns) { column in
                    columnRow(column)
                }
            } header: {
                Text("Columns")
            } footer: {
                if !model.mapping.isReady {
                    Text("Choose which column is the item name.")
                        .foregroundStyle(.orange)
                } else {
                    Text("Anything you leave as Ignore is not imported. Choose Add to notes to keep a column's contents in each item's notes.")
                }
            }
        }
        .navigationTitle("Match Your Columns")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Continue") { onContinue() }
                    .disabled(!model.mapping.isReady)
            }
        }
    }

    private func columnRow(_ column: ImportColumn) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(column.label)
                    .font(.body)
                    .lineLimit(2)
                if !column.samples.isEmpty {
                    Text(column.samples.joined(separator: "  ·  "))
                        .font(.caption)
                        .foregroundStyle(Color(.secondaryLabel))
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            Picker("Role for \(column.label)", selection: Binding(
                get: { model.mapping.roles.indices.contains(column.index) ? model.mapping.roles[column.index] : .ignore },
                set: { model.setRole($0, forColumn: column.index) }
            )) {
                ForEach(ImportRole.menuOrder, id: \.self) { role in
                    Text(role.title).tag(role)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(.teal)
        }
        .padding(.vertical, 2)
    }
}
