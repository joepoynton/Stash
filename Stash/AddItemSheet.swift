//
//  AddItemSheet.swift
//  Stash
//

import SwiftUI
import SwiftData

struct AddItemSheet: View {
    let location: Location

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var notes = ""
    @State private var trackQuantity = false
    @State private var quantity = 0
    @State private var unit = ""
    @State private var minimumQuantity = 0
    @State private var hasExpiryDate = false
    @State private var expiryDate = Date()

    @FocusState private var nameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .focused($nameFocused)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    Toggle("Track Quantity", isOn: $trackQuantity.animation())
                    if trackQuantity {
                        Stepper("Quantity: \(quantity)", value: $quantity, in: 0...9999)
                        HStack {
                            Text("Unit")
                            Spacer()
                            TextField("e.g. rolls, tablets", text: $unit)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 160)
                        }
                        Stepper("Minimum: \(minimumQuantity)", value: $minimumQuantity, in: 0...9999)
                    }
                }

                Section {
                    Toggle("Expiry Date", isOn: $hasExpiryDate.animation())
                    if hasExpiryDate {
                        DatePicker("Date", selection: $expiryDate, displayedComponents: .date)
                    }
                }
            }
            .navigationTitle("New Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { nameFocused = true }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let item = Item(name: trimmed, location: location)
        item.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil
                     : notes.trimmingCharacters(in: .whitespacesAndNewlines)

        if trackQuantity {
            item.quantity = quantity
            let trimmedUnit = unit.trimmingCharacters(in: .whitespaces)
            item.unit = trimmedUnit.isEmpty ? nil : String(trimmedUnit.prefix(20))
            item.minimumQuantity = minimumQuantity > 0 ? minimumQuantity : nil
        }

        item.expiryDate = hasExpiryDate ? expiryDate : nil
        modelContext.insert(item)
        dismiss()
    }
}
