//
//  Location.swift
//  Stash
//

import Foundation
import SwiftData

@Model
final class Location {
    var id: UUID = UUID()
    var name: String = ""
    var icon: String?          // SF Symbol name. Root nodes only per spec — retained on demotion.
    var photo: Data?           // Compressed JPEG. Max 1200px long edge.
    var color: String?         // Hex string. Root nodes only — retained on demotion.
    var parent: Location?
    @Relationship(deleteRule: .nullify, inverse: \Location.parent)
    var children: [Location]?
    @Relationship(deleteRule: .cascade, inverse: \Item.location)
    var items: [Item]?
    var dateCreated: Date = Date()
    var isStarred: Bool = false  // Reserved for v1.1. Always false in v1.
    /// Manual sort position within siblings. 0 = unset (sort alphabetically).
    /// Once any sibling is manually reordered, all get explicit values starting from 1.
    var sortOrder: Int = 0

    init(
        name: String,
        icon: String? = nil,
        color: String? = nil,
        parent: Location? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.icon = icon
        self.color = color
        self.parent = parent
        self.dateCreated = Date()
        self.isStarred = false
    }

    /// True if this location is a root node (Area).
    var isRoot: Bool { parent == nil }

    /// Safe accessors — CloudKit requires these relationships be stored as optionals,
    /// but throughout the app we treat them as always-present empty arrays.
    var childList: [Location] { children ?? [] }
    var itemList: [Item] { items ?? [] }

    /// True if any descendant item is below its minimum quantity and not on order.
    /// Used to show the low-stock dot on Area cards.
    var hasLowStockDescendant: Bool {
        let hasLowItem = itemList.contains { item in
            guard let qty = item.quantity, let min = item.minimumQuantity else { return false }
            return qty < min && item.orderStatusRaw != OrderStatus.onOrder.rawValue
        }
        return hasLowItem || childList.contains { $0.hasLowStockDescendant }
    }
}
