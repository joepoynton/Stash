//
//  SettingsView.swift
//  Stash
//
//  Stub settings screen. Full implementation is Phase 8.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Settings coming in Phase 8.")
                        .foregroundStyle(Color(.secondaryLabel))
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
