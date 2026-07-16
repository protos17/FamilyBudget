//
//  ListItem.swift
//  CloudKitSharing
//
//  A single item in a shared list. Tracks who created it so the
//  PermissionManager can enforce "only creator or owner can delete".
//

import Foundation
import SwiftData

@Model
final class Transaction {
    var id: UUID = UUID()
    var text: String = ""
    var createdAt: Date = Date()
    var date: Date = Date()
    /// Last time this item was confirmed in CloudKit.
    /// Used by sync logic to avoid re-uploading items that were deleted remotely.
    var modifiedAt: Date?

    /// CloudKit user record name of the person who created this item.
    /// Used for permission checks in shared lists.
    var createdByUserID: String?

    /// Parent list
    var list: Account?

    init(
        id: UUID = UUID(),
        text: String,
        createdByUserID: String? = nil
    ) {
        self.id = id
        self.text = text
        self.createdByUserID = createdByUserID
    }
}
