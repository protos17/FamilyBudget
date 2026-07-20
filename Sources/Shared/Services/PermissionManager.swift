//
//  PermissionManager.swift
//  CloudKitSharing
//
//  Centralized permission checks for shared lists.
//
//  WHY THIS EXISTS
//  ───────────────
//  In a shared list, not everyone can do everything:
//
//  │ Action              │ Owner │ Member │
//  │─────────────────────│───────│────────│
//  │ Add items           │  ✓    │   ✓    │
//  │ Edit any item       │  ✓    │   ✓    │
//  │ Delete own items    │  ✓    │   ✓    │
//  │ Delete others' items│  ✓    │   ✗    │
//  │ Edit list metadata  │  ✓    │   ✗    │
//  │ Delete list         │  ✓    │   ✗    │
//  │ Manage sharing      │  ✓    │   ✗    │
//  │ Leave shared list   │  ✗    │   ✓    │
//
//  Every view checks PermissionManager before enabling destructive actions.
//  This prevents the UI from showing actions the server would reject anyway.
//

@MainActor
final class PermissionManager {
    static let shared = PermissionManager()

    var userIdentity: UserIdentityProviding = UserIdentityService.shared

    private init() {}

    /// Initializer for testing with a mock identity provider
    init(userIdentity: UserIdentityProviding) {
        self.userIdentity = userIdentity
    }

    // MARK: - Item Permissions

    /// Can the current user add items to this list?
    func canAddItem(to list: Account) -> Bool {
        // Non-shared lists: always allowed
        guard list.isShared else { return true }
        // Shared lists: anyone with access can add
        return true
    }

    /// Can the current user edit this item?
    func canEdit(item: Transaction, in list: Account) -> Bool {
        guard canAddItem(to: list) else { return false }
        // In shared lists, any member with write access can edit
        return true
    }

    /// Can the current user delete this item?
    func canDelete(item: Transaction, in list: Account) -> Bool {
        guard canAddItem(to: list) else { return false }
        guard list.isShared else { return true }

        // Owner can delete anything
        if userIdentity.isCurrentUserOwner(of: list) { return true }
        // Members can only delete items they created
        if userIdentity.didCurrentUserCreate(item) { return true }

        return false
    }

    // MARK: - List Permissions

    /// Can the current user edit list metadata (name, color, icon)?
    func canEditListMetadata(_ list: Account) -> Bool {
        userIdentity.isCurrentUserOwner(of: list)
    }

    /// Can the current user delete this list?
    func canDeleteList(_ list: Account) -> Bool {
        userIdentity.isCurrentUserOwner(of: list)
    }

    /// Can the current user manage sharing (add/remove members, stop sharing)?
    func canManageSharing(for list: Account) -> Bool {
        userIdentity.isCurrentUserOwner(of: list)
    }

    /// Can the current user leave this shared list?
    func canLeaveList(_ list: Account) -> Bool {
        guard list.isShared else { return false }
        return !userIdentity.isCurrentUserOwner(of: list)
    }

    /// Can the current user initiate sharing for this list?
    func canShareList(_ list: Account) -> Bool {
        guard !list.isShared else { return false }
        guard userIdentity.isCurrentUserOwner(of: list) else { return false }
        guard userIdentity.isCloudKitAvailable else { return false }
        guard !(list.transactions ?? []).isEmpty else { return false }   // ← новая проверка
        return true
    }
}
