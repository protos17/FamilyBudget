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
final class ListItem {
    var id: UUID = UUID()
    var text: String = ""
    var createdAt: Date = Date()
    var modifiedAt: Date? = nil

    /// CloudKit user record name of the person who created this item.
    /// Used for permission checks in shared lists.
    var createdByUserID: String? = nil

    /// Parent list
    var list: ItemList? = nil

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
