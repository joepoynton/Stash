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

    // Direct numeric entry for quantity
    @State private var editingQuantity = false
    @State private var quantityEntryText = ""
    @FocusState private var quantityFieldFocused: Bool

    // Direct numeric entry for minimum
    @State private var editingMinimum = false
    @State private var minimumEntryText = ""
    @FocusState private var minimumFieldFocused: Bool

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
                        // Current quantity
                        HStack {
                            Button {
                                guard quantity > 0 else { return }
                                quantity -= 1
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(quantity == 0 ? Color(.tertiaryLabel) : .teal)
                            }
                            .buttonStyle(.plain)
                            .disabled(quantity == 0)

                            Spacer()

                            quantityDisplay

                            Spacer()

                            Button {
                                quantity += 1
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.teal)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)

                        // Unit
                        HStack {
                            Text("Unit")
                            Spacer()
                            TextField("e.g. rolls, tablets", text: $unit)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 160)
                        }

                        // Minimum quantity
                        HStack {
                            Text("Minimum")
                                .foregroundStyle(Color(.label))

                            Spacer()

                            Button {
                                guard minimumQuantity > 0 else { return }
                                minimumQuantity -= 1
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(minimumQuantity == 0 ? Color(.tertiaryLabel) : .teal)
                            }
                            .buttonStyle(.plain)
                            .disabled(minimumQuantity == 0)

                            minimumDisplay

                            Button {
                                minimumQuantity += 1
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.teal)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
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
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    if editingQuantity {
                        Button("Done") { commitQuantityEntry() }
                    } else if editingMinimum {
                        Button("Done") { commitMinimumEntry() }
                    }
                }
            }
            .onChange(of: quantityFieldFocused) { _, isFocused in
                if !isFocused && editingQuantity { commitQuantityEntry() }
            }
            .onChange(of: minimumFieldFocused) { _, isFocused in
                if !isFocused && editingMinimum { commitMinimumEntry() }
            }
            .onAppear { nameFocused = true }
        }
    }

    // MARK: - Quantity display

    @ViewBuilder
    private var quantityDisplay: some View {
        if editingQuantity {
            TextField("0", text: $quantityEntryText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.title.monospacedDigit())
                .focused($quantityFieldFocused)
                .frame(minWidth: 60)
        } else {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(quantity)")
                    .font(.title.monospacedDigit())
                    .foregroundStyle(Color(.label))
                    .underline(color: Color(.tertiaryLabel))
                if !unit.isEmpty {
                    Text(unit)
                        .font(.title3)
                        .foregroundStyle(Color(.secondaryLabel))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                quantityEntryText = "\(quantity)"
                editingQuantity = true
                quantityFieldFocused = true
            }
        }
    }

    @ViewBuilder
    private var minimumDisplay: some View {
        if editingMinimum {
            TextField("0", text: $minimumEntryText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.title.monospacedDigit())
                .focused($minimumFieldFocused)
                .frame(minWidth: 60)
        } else {
            Text("\(minimumQuantity)")
                .font(.title.monospacedDigit())
                .foregroundStyle(Color(.label))
                .underline(color: Color(.tertiaryLabel))
                .contentShape(Rectangle())
                .onTapGesture {
                    minimumEntryText = "\(minimumQuantity)"
                    editingMinimum = true
                    minimumFieldFocused = true
                }
        }
    }

    // MARK: - Commit helpers

    private func commitQuantityEntry() {
        guard editingQuantity else { return }
        if let value = Int(quantityEntryText) {
            quantity = max(0, value)
        }
        editingQuantity = false
        quantityEntryText = ""
        quantityFieldFocused = false
    }

    private func commitMinimumEntry() {
        guard editingMinimum else { return }
        if let value = Int(minimumEntryText) {
            minimumQuantity = max(0, value)
        }
        editingMinimum = false
        minimumEntryText = ""
        minimumFieldFocused = false
    }

    // MARK: - Save

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
