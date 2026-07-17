//
//  ListItem.swift
//  CloudKitSharing
//
//  A single item in a shared list. Tracks who created it so the
//  PermissionManager can enforce "only creator or owner can delete".
//

import Foundation
import SwiftData

enum TransactionType: String, Codable {
    case income
    case expense
}

enum PaymentMethod: String, Codable {
    case cash
    case card
    case transfer
    case other
}

@Model
final class Transaction {
    var id: UUID = UUID()
    var title: String = ""
    var amountMinorUnits: Int = 0
    var type: TransactionType = TransactionType.expense
    var date: Date = Date()
    var note: String?
    var paymentMethod: PaymentMethod = PaymentMethod.other
    var tags: [String] = []
    var createdAt: Date = Date()
    var modifiedAt: Date?
    var createdByUserID: String?
    var createdByDisplayName: String?
    var account: Account?
    var category: Category?
    var amount: Decimal {
        Decimal(amountMinorUnits) / 100
    }

    init(
        id: UUID = UUID(),
        title: String,
        amountMinorUnits: Int,
        type: TransactionType,
        date: Date = .now,
        createdByUserID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.amountMinorUnits = amountMinorUnits
        self.type = type
        self.date = date
        self.createdByUserID = createdByUserID
    }
}
