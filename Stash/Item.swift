//
//  Item.swift
//  Stash
//

import Foundation
import SwiftData

// MARK: - OrderStatus

/// The restock state of an item.
/// `.low` is derived (quantity < minimumQuantity) and never stored directly.
/// Only `.normal` and `.onOrder` are persisted via `orderStatusRaw`.
enum OrderStatus: String, Codable, Equatable {
    case normal
    case low      // Derived — not stored. Computed from quantity vs minimumQuantity.
    case onOrder  // User-set via Restock tab.
}

// MARK: - Item

@Model
final class Item {
    var id: UUID = UUID()
    var name: String = ""
    var notes: String?
    @Attribute(.externalStorage)
    var photo: Data?           // Compressed JPEG. Max 1200px long edge.
    var quantity: Int?         // Nil = quantity tracking off.
    var unit: String?          // Free text, max 20 chars. Shown next to quantity.
    var minimumQuantity: Int?  // Only meaningful when quantity != nil.
    var expiryDate: Date?
    /// Backing store for orderStatus. Only holds "normal" or "onOrder".
    var orderStatusRaw: String = OrderStatus.normal.rawValue
    var dateAdded: Date = Date()
    var lastVerified: Date = Date()
    var isStarred: Bool = false  // Reserved for v1.1. Always false in v1.
    var neverStale: Bool = false // When true, item is exempt from stale/unverified checking.
    var manuallyRestocking: Bool = false // User-pushed to Restock regardless of stock level.
    var isOutOfPlace: Bool = false     // Item is temporarily not in its home location.
    var outOfPlaceNote: String?        // Optional note e.g. "Lent to Dad", "In use in kitchen".
    var location: Location?      // Optional for CloudKit compatibility. Required in app logic.

    init(name: String, location: Location? = nil) {
        self.id = UUID()
        self.name = name
        self.location = location
        self.orderStatusRaw = OrderStatus.normal.rawValue
        self.dateAdded = Date()
        self.lastVerified = Date()
        self.isStarred = false
    }

    /// The effective order status, incorporating the derived `.low` state.
    /// `.low` is returned when quantity < minimumQuantity and the item is not on order.
    /// Setting this property to `.low` is a no-op; the low state is always derived.
    var orderStatus: OrderStatus {
        get {
            if let qty = quantity, let min = minimumQuantity, qty < min,
               orderStatusRaw != OrderStatus.onOrder.rawValue {
                return .low
            }
            return OrderStatus(rawValue: orderStatusRaw) ?? .normal
        }
        set {
            guard newValue != .low else { return }
            orderStatusRaw = newValue.rawValue
        }
    }

    // MARK: - Model-layer write operations
    // Implemented here (not in views) so AppIntents can wrap them in v1.5.

    func updateQuantity(to newQuantity: Int) {
        quantity = max(0, newQuantity)
        clearOrderStatusIfRestocked()
        lastVerified = Date()
    }

    func incrementQuantity() {
        quantity = (quantity ?? 0) + 1
        clearOrderStatusIfRestocked()
        lastVerified = Date()
    }

    func decrementQuantity() {
        guard let qty = quantity, qty > 0 else { return }
        quantity = qty - 1
        lastVerified = Date()
    }

    func markAsVerified() {
        lastVerified = Date()
    }

    func markAsOrdered() {
        orderStatusRaw = OrderStatus.onOrder.rawValue
    }

    /// If the user restocks via +/quantity edits instead of "Mark as Arrived",
    /// the onOrder flag would otherwise stick forever with no way to clear it.
    private func clearOrderStatusIfRestocked() {
        guard orderStatusRaw == OrderStatus.onOrder.rawValue,
              let qty = quantity, let min = minimumQuantity, qty >= min else { return }
        orderStatusRaw = OrderStatus.normal.rawValue
    }

    func returnToPlace() {
        isOutOfPlace = false
        outOfPlaceNote = nil
        lastVerified = Date()
    }

    /// "Replaced it" on an expiring/expired item. The new product's expiry
    /// isn't known at swipe time, so the date is cleared rather than guessed;
    /// the user can set the real date from the detail sheet later.
    func markAsReplaced() {
        expiryDate = nil
        lastVerified = Date()
    }

    /// Records arrival of `count` units. Resets order status. Updates lastVerified.
    /// Quantity is only adjusted when tracking is already on — arrival must
    /// never silently switch quantity tracking on for an untracked item.
    func markAsArrived(count: Int) {
        if quantity != nil {
            quantity = (quantity ?? 0) + count
        }
        orderStatusRaw = OrderStatus.normal.rawValue
        manuallyRestocking = false
        lastVerified = Date()
    }
}
