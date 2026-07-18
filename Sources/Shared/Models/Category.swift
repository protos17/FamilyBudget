//
//  Category.swift
//  CloudKitSharing
//
//  Created by Danil on 16.07.2026.
//

import Foundation
import SwiftData

enum CategoryKind: String, Codable {
    case income
    case expense
    case universal
}

@Model
final class Category {
    var id: UUID = UUID()
    var name: String = ""
    var icon: String = "tag"
    var colorHex: String = "FF9500"
    var kind: CategoryKind = CategoryKind.universal
    var createdAt: Date = Date()
    var sortOrder: Int = 0

    var account: Account?
    
    @Relationship(deleteRule: .nullify, inverse: \Transaction.category)
    var transactions: [Transaction]?

    init(
        id: UUID = UUID(),
        name: String,
        icon: String = "tag",
        colorHex: String = "FF9500",
        kind: CategoryKind = .universal,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.kind = kind
        self.sortOrder = sortOrder
    }
}
