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
    var title: String = ""                      // было text
    var amountMinorUnits: Int = 0                // сумма в копейках/центах
    var type: TransactionType = TransactionType.expense
    var date: Date = Date()                      // дата операции
    var note: String?
    var paymentMethod: PaymentMethod = PaymentMethod.other
    var tags: [String] = []
    var createdAt: Date = Date()

    /// Last time this item was confirmed in CloudKit.
    /// Used by sync logic to avoid re-uploading items that were deleted remotely.
    var modifiedAt: Date?

    /// CloudKit user record name of the person who created this item.
    /// Used for permission checks in shared lists.
    var createdByUserID: String?

    /// Кэш имени автора для быстрого отображения в UI без похода в UserIdentityService
    var createdByDisplayName: String?

    /// Parent account
    var account: Account?

    /// Категория операции
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
