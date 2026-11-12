//
//  BackupRestore.swift
//  Stash
//
//  Reading a Stash backup (the JSON file made by Settings › Export Data) back
//  in. Moved out of SettingsView in 1.3 so a backup opened from Files or the
//  share sheet can be restored from outside Settings too. Behaviour is the
//  same as before: decode and count, ask for confirmation, then add the areas
//  and items alongside whatever is already there.
//

import SwiftUI
import SwiftData

// MARK: - Decoded backup

struct BackupRoot: Decodable {
    let appVersion: String?
    let exportDate: Date?
    let areas: [BackupLocation]
}

struct BackupLocation: Decodable {
    let name: String
    let icon: String?
    let color: String?
    let sortOrder: Int?            // Optional: older exports omit it.
    let children: [BackupLocation]?
    let items: [BackupItem]?

    /// Total items in this subtree, used for the pre-import confirmation count.
    var itemCount: Int {
        (items?.count ?? 0) + (children?.reduce(0) { $0 + $1.itemCount } ?? 0)
    }
}

struct BackupItem: Decodable {
    let name: String
    let notes: String?
    let quantity: Int?
    let unit: String?
    let minimumQuantity: Int?
    let expiryDate: Date?
    let orderStatus: String?
    // Optional: older exports omit these (D6, backward-compatible).
    let isOutOfPlace: Bool?
    let outOfPlaceNote: String?
    let neverStale: Bool?
    let manuallyRestocking: Bool?
    let dateAdded: Date?
    let lastVerified: Date?
}

// MARK: - Restore

enum BackupRestore {

    /// A decoded backup waiting for the user's confirmation.
    struct Pending {
        let root: BackupRoot
        let areaCount: Int
        let itemCount: Int

        var confirmationMessage: String {
            "This will add \(areaCount) \(areaCount == 1 ? "area" : "areas") and \(itemCount) \(itemCount == 1 ? "item" : "items") alongside your existing data."
        }
    }

    static let invalidFileMessage = "The file is not a valid Stash export."

    /// Nil if the data isn't a Stash export.
    static func decode(_ data: Data) -> Pending? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let root = try? decoder.decode(BackupRoot.self, from: data) else { return nil }
        return Pending(
            root: root,
            areaCount: root.areas.count,
            itemCount: root.areas.reduce(0) { $0 + $1.itemCount }
        )
    }

    /// Performs the insert from the decoded, in-memory backup and returns the
    /// message for the result alert. Enforces the free-tier item cap so a
    /// restore can never push a free user over the limit (D6); locations
    /// themselves are not capped.
    static func commit(_ pending: Pending, in context: ModelContext, existingItemCount: Int, isPro: Bool) -> String {
        var remaining = isPro ? Int.max : max(0, FeatureFlags.freeItemLimit - existingItemCount)
        var importedCount = 0
        var skipped = 0

        for area in pending.root.areas {
            let location = Location(name: area.name, icon: area.icon, color: area.color, parent: nil)
            location.sortOrder = area.sortOrder ?? 0
            context.insert(location)
            insertChildren(of: area, into: location, context: context, remaining: &remaining, importedCount: &importedCount, skipped: &skipped)
        }

        try? context.save()

        let areaWord = pending.areaCount == 1 ? "area" : "areas"
        let itemWord = importedCount == 1 ? "item" : "items"
        if skipped > 0 {
            let skippedWord = skipped == 1 ? "item was" : "items were"
            return "Imported \(pending.areaCount) \(areaWord) and \(importedCount) \(itemWord). \(skipped) \(skippedWord) skipped because the free plan is limited to \(FeatureFlags.freeItemLimit) items. Upgrade to Stash Pro for unlimited items."
        }
        return "Imported \(pending.areaCount) \(areaWord) and \(importedCount) \(itemWord)."
    }

    private static func insertChildren(
        of node: BackupLocation,
        into location: Location,
        context: ModelContext,
        remaining: inout Int,
        importedCount: inout Int,
        skipped: inout Int
    ) {
        for importedChild in node.children ?? [] {
            let child = Location(name: importedChild.name, icon: importedChild.icon, color: importedChild.color, parent: location)
            child.sortOrder = importedChild.sortOrder ?? 0
            context.insert(child)
            insertChildren(of: importedChild, into: child, context: context, remaining: &remaining, importedCount: &importedCount, skipped: &skipped)
        }
        for importedItem in node.items ?? [] {
            guard remaining > 0 else {
                skipped += 1
                continue
            }
            let item = Item(name: importedItem.name, location: location)
            item.notes = importedItem.notes
            item.quantity = importedItem.quantity
            item.unit = importedItem.unit
            item.minimumQuantity = importedItem.minimumQuantity
            item.expiryDate = importedItem.expiryDate
            if importedItem.orderStatus == OrderStatus.onOrder.rawValue {
                item.orderStatusRaw = OrderStatus.onOrder.rawValue
            }
            // D6: round-trip the previously-omitted state.
            item.isOutOfPlace = importedItem.isOutOfPlace ?? false
            item.outOfPlaceNote = importedItem.outOfPlaceNote
            // New items default to 'always verified'; honour an explicit value
            // from a Stash export, otherwise default to true.
            item.neverStale = importedItem.neverStale ?? true
            item.manuallyRestocking = importedItem.manuallyRestocking ?? false
            if let dateAdded = importedItem.dateAdded { item.dateAdded = dateAdded }
            if let lastVerified = importedItem.lastVerified { item.lastVerified = lastVerified }
            context.insert(item)
            importedCount += 1
            remaining -= 1
        }
    }
}

// MARK: - Confirmation outside Settings

/// Asks "Restore from Backup?" and reports the result, for a backup that
/// arrives while the user isn't in Settings (opened from Files, Mail or the
/// share sheet). Set `data` to start; it is cleared once picked up.
private struct BackupRestorePrompt: ViewModifier {
    @Binding var data: Data?

    @Environment(\.modelContext) private var modelContext
    @Environment(StoreKitManager.self) private var storeKit

    @State private var pending: BackupRestore.Pending?
    @State private var confirmMessage = ""
    @State private var showConfirm = false
    @State private var resultTitle = ""
    @State private var resultMessage = ""
    @State private var showResult = false

    func body(content: Content) -> some View {
        content
            .onChange(of: data) { _, newValue in
                guard let newValue else { return }
                data = nil
                guard let decoded = BackupRestore.decode(newValue) else {
                    resultTitle = "Restore Failed"
                    resultMessage = BackupRestore.invalidFileMessage
                    showResult = true
                    return
                }
                pending = decoded
                confirmMessage = decoded.confirmationMessage
                showConfirm = true
            }
            .alert("Restore from Backup?", isPresented: $showConfirm) {
                Button("Restore") { commit() }
                Button("Cancel", role: .cancel) { pending = nil }
            } message: {
                Text(confirmMessage)
            }
            .alert(resultTitle, isPresented: $showResult) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(resultMessage)
            }
    }

    private func commit() {
        guard let pending else { return }
        self.pending = nil
        let existing = (try? modelContext.fetchCount(FetchDescriptor<Item>())) ?? 0
        resultTitle = "Restore Complete"
        resultMessage = BackupRestore.commit(pending, in: modelContext, existingItemCount: existing, isPro: storeKit.isPro)
        showResult = true
    }
}

extension View {
    func backupRestorePrompt(data: Binding<Data?>) -> some View {
        modifier(BackupRestorePrompt(data: data))
    }
}
