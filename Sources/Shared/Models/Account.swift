//
//  ItemList.swift
//  CloudKitSharing
//
//  A shareable list of items. Equivalent to a "Space" or "Folder" in a
//  real app. This is the unit of collaboration — you share an entire list,
//  not individual items.
//
//  SHARING FIELDS
//  ──────────────
//  isShared          – true once a CKShare has been created for this list
//  ownerID           – CloudKit user record name of the person who created the share
//  shareRecordID     – the CKRecord.ID.recordName of the CKShare (for fetching)
//  shareZoneOwnerName – CKRecordZone.ID.ownerName (needed by invitees to query the shared zone)
//  isPro             – placeholder for subscription gating (always true in this demo)
//

import Foundation
import SwiftData

@Model
final class Account {
    var id: UUID = UUID()
    var name: String = ""
    var icon: String = "creditcard"
    var colorHex: String = "007AFF"
    var currencyCode: String = "RUB"
    var createdAt: Date = Date()
    var sortOrder: Int = 0

    // MARK: - Sharing Metadata

    /// Whether this list is currently shared via CloudKit
    var isShared: Bool = false

    /// CloudKit user record name of the list owner
    var ownerID: String?

    /// CKShare record name — used to fetch the share when managing participants
    var shareRecordID: String?

    /// CKRecordZone.ID.ownerName — invitees need this to query the shared zone
    var shareZoneOwnerName: String?

    /// Timestamp of last CloudKit sync for this list
    var lastSharedUpdatedAt: Date?

    /// Whether the owner has an active subscription (always true in this demo)
    var isPro: Bool = true

    // MARK: - Relationships

    @Relationship(deleteRule: .cascade)
    var transactions: [Transaction]? = []

    @Relationship(deleteRule: .cascade)
    var categories: [Category]? = []

    var sortedTransactions: [Transaction] {
        transactions?.sorted(by: { $0.date > $1.date }) ?? []
    }

    var sortedCategories: [Category] {
        (categories ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    init(
        id: UUID = UUID(),
        name: String,
        icon: String = "creditcard",
        colorHex: String = "007AFF",
        currencyCode: String = "RUB",
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.currencyCode = currencyCode
        self.sortOrder = sortOrder
    }
}

