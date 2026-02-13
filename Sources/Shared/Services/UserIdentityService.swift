//
//  UserIdentityService.swift
//  CloudKitSharing
//
//  Resolves the current CloudKit user identity.
//
//  WHY THIS EXISTS
//  ───────────────
//  When multiple people share a list, we need to know WHO the current user
//  is so we can check:
//    • Are they the owner of this list? (can manage sharing, delete list)
//    • Did they create this item? (can delete their own items)
//
//  The service fetches the CloudKit user record ID on launch and caches it.
//  If CloudKit is unavailable (user not signed in), it falls back to a
//  stable local device identifier.
//

import CloudKit

/// Protocol for dependency injection in tests
@MainActor
protocol UserIdentityProviding {
    var currentUserID: String? { get }
    var isCloudKitAvailable: Bool { get }
    func isCurrentUserOwner(of list: ItemList) -> Bool
    func didCurrentUserCreate(_ item: ListItem) -> Bool
}

@MainActor
@Observable
final class UserIdentityService: UserIdentityProviding {
    static let shared = UserIdentityService()

    private(set) var currentUserID: String?
    private(set) var isFetchingIdentity = false

    /// Stable local device ID as fallback when CloudKit is unavailable
    private let localDeviceID: String

    private init() {
        if let existing = UserDefaults.standard.string(forKey: "localDeviceIdentifier") {
            localDeviceID = existing
        } else {
            localDeviceID = UUID().uuidString
            UserDefaults.standard.set(localDeviceID, forKey: "localDeviceIdentifier")
        }

        Task {
            await fetchUserIdentity()
        }
    }

    /// Fetches the current user's CloudKit record ID
    func fetchUserIdentity() async {
        guard !isFetchingIdentity else { return }
        isFetchingIdentity = true
        defer { isFetchingIdentity = false }

        do {
            let container = CKContainer(identifier: AppConstants.cloudKitContainerID)
            let userRecordID = try await container.userRecordID()
            currentUserID = userRecordID.recordName
        } catch {
            currentUserID = localDeviceID
        }
    }

    /// Waits for identity to be resolved before critical operations
    func ensureIdentityResolved() async {
        if currentUserID != nil && currentUserID != localDeviceID { return }

        if isFetchingIdentity {
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(100))
                if !isFetchingIdentity && currentUserID != nil { return }
            }
        }

        await fetchUserIdentity()
    }

    // MARK: - Permission Helpers

    func isCurrentUserOwner(of list: ItemList) -> Bool {
        guard let ownerID = list.ownerID else {
            // No owner set → current user is owner (pre-sharing state)
            return true
        }
        return ownerID == currentUserID
    }

    func didCurrentUserCreate(_ item: ListItem) -> Bool {
        guard let creatorID = item.createdByUserID else {
            return true // No creator recorded → assume local
        }
        return creatorID == currentUserID
    }

    var isCloudKitAvailable: Bool {
        if let userID = currentUserID {
            return userID != localDeviceID
        }
        return true // Optimistic while fetching
    }
}
