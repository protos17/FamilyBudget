//
//  SharingManager.swift
//  CloudKitSharing
//
//  Manages CloudKit sharing for collaborative lists.
//
//  HOW CLOUDKIT SHARING WORKS
//  ──────────────────────────
//  1. Owner creates a CKShare linked to a root CKRecord in a CUSTOM ZONE
//     (records in the default zone cannot be shared)
//  2. Owner sends an invite link (UICloudSharingController handles this UI)
//  3. Invitee taps the link → iOS calls userDidAcceptCloudKitShareWith
//  4. Invitee accepts the share → CKAcceptSharesOperation
//  5. Both sides can now read/write the shared zone
//     - Owner uses privateCloudDatabase
//     - Invitee uses sharedCloudDatabase (with owner's zone ID)
//
//  KEY INSIGHT: The owner and invitee access DIFFERENT databases but the
//  SAME logical zone. The invitee must use the owner's zone name AND the
//  owner's record name (shareZoneOwnerName) to construct the correct zone ID.
//

import Foundation
import CloudKit
import SwiftData
import OSLog

@Observable
@MainActor
final class SharingManager {
    static let shared = SharingManager()

    private let logger = Logger(subsystem: "com.example.cloudkitsharing", category: "Sharing")

    /// Notification posted when a shared list becomes unavailable
    static let sharingEndedNotification = Notification.Name("SharingManager.sharingEnded")

    // MARK: - CloudKit Configuration

    private var _container: CKContainer?
    private var container: CKContainer {
        if _container == nil {
            _container = CKContainer(identifier: AppConstants.cloudKitContainerID)
        }
        return _container!
    }

    /// CRITICAL: Sharing requires a custom zone. Default zone records cannot be shared.
    private let sharingZone = CKRecordZone(zoneName: "SharedLists")
    private var zoneCreated = false

    private let listRecordType = "SharedList"
    private let itemRecordType = "SharedListItem"

    private init() {}

    // MARK: - Share Creation

    /// Creates a CKShare for a list, or returns the existing one.
    /// This is called when the user taps "Share" on a list.
    func fetchOrCreateShare(
        for list: ItemList,
        context: ModelContext
    ) async throws -> (CKShare, CKContainer) {
        // If the list already has a share, fetch and return it
        if list.isShared, let shareRecordName = list.shareRecordID {
            let share = try await fetchExistingShare(recordName: shareRecordName, for: list)
            return (share, container)
        }

        // 1. Ensure the custom zone exists
        try await ensureZoneExists()

        // 2. Ensure identity is resolved so we can set ownerID
        await UserIdentityService.shared.ensureIdentityResolved()

        // 3. Create a root record for the list in the custom zone
        let listRecordID = CKRecord.ID(
            recordName: "List-\(list.id.uuidString)",
            zoneID: sharingZone.zoneID
        )
        let listRecord = CKRecord(recordType: listRecordType, recordID: listRecordID)
        listRecord["listID"] = list.id.uuidString as CKRecordValue
        listRecord["name"] = list.name as CKRecordValue
        listRecord["icon"] = list.icon as CKRecordValue
        listRecord["colorHex"] = list.colorHex as CKRecordValue

        // 4. Create a CKShare linked to the root record
        let share = CKShare(rootRecord: listRecord)
        share[CKShare.SystemFieldKey.title] = list.name as CKRecordValue
        share.publicPermission = .none // Private sharing only

        // 5. Save both the root record and share in one operation
        let operation = CKModifyRecordsOperation(
            recordsToSave: [listRecord, share],
            recordIDsToDelete: nil
        )
        operation.isAtomic = true

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            self.container.privateCloudDatabase.add(operation)
        }

        // 6. Update local model with sharing metadata
        list.isShared = true
        list.ownerID = UserIdentityService.shared.currentUserID
        list.shareRecordID = share.recordID.recordName
        list.shareZoneOwnerName = share.recordID.zoneID.ownerName
        list.isPro = true
        list.lastSharedUpdatedAt = Date()
        try? context.save()

        logger.info("Created share for list '\(list.name)'")
        return (share, container)
    }

    /// Fetches an existing CKShare by its record name
    private func fetchExistingShare(recordName: String, for list: ItemList) async throws -> CKShare {
        let isOwner = UserIdentityService.shared.isCurrentUserOwner(of: list)

        let zoneID: CKRecordZone.ID
        if isOwner {
            zoneID = sharingZone.zoneID
        } else if let ownerName = list.shareZoneOwnerName {
            zoneID = CKRecordZone.ID(zoneName: sharingZone.zoneID.zoneName, ownerName: ownerName)
        } else {
            throw SharingError.invalidShare
        }

        let shareRecordID = CKRecord.ID(recordName: recordName, zoneID: zoneID)
        let database = isOwner ? container.privateCloudDatabase : container.sharedCloudDatabase

        let record = try await database.record(for: shareRecordID)
        guard let share = record as? CKShare else {
            throw SharingError.shareNotFound
        }
        return share
    }

    // MARK: - Share Acceptance

    /// Accepts an incoming share invitation.
    /// Called from the app delegate when iOS delivers CKShare.Metadata.
    func acceptShare(
        _ metadata: CKShare.Metadata,
        context: ModelContext
    ) async throws -> ItemList {
        await UserIdentityService.shared.ensureIdentityResolved()

        // Accept the share via CloudKit
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKAcceptSharesOperation(shareMetadatas: [metadata])
            operation.acceptSharesResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            self.container.add(operation)
        }

        // Fetch the shared root record to get list metadata
        let rootRecordID = metadata.rootRecordID
        let record = try await container.sharedCloudDatabase.record(for: rootRecordID)

        // Create or find the local ItemList
        let listID: UUID
        if let idString = record["listID"] as? String, let uuid = UUID(uuidString: idString) {
            listID = uuid
        } else {
            listID = UUID()
        }

        // Check if list already exists locally
        let descriptor = FetchDescriptor<ItemList>(predicate: #Predicate { $0.id == listID })
        if let existing = try? context.fetch(descriptor).first {
            logger.info("Share accepted — list '\(existing.name)' already exists locally")
            return existing
        }

        // Create new local list from the shared record
        let list = ItemList(
            id: listID,
            name: (record["name"] as? String) ?? "Shared List",
            icon: (record["icon"] as? String) ?? "list.bullet",
            colorHex: (record["colorHex"] as? String) ?? "007AFF"
        )
        list.isShared = true
        list.ownerID = metadata.ownerIdentity.userRecordID?.recordName
        list.shareRecordID = metadata.share.recordID.recordName
        list.shareZoneOwnerName = rootRecordID.zoneID.ownerName
        list.isPro = true
        list.lastSharedUpdatedAt = Date()

        context.insert(list)
        try? context.save()

        logger.info("Share accepted — created list '\(list.name)'")
        return list
    }

    // MARK: - Stop Sharing

    /// Owner stops sharing a list. Removes the CKShare.
    func stopSharing(_ list: ItemList, context: ModelContext) async throws {
        guard list.isShared else { throw SharingError.notShared }
        guard UserIdentityService.shared.isCurrentUserOwner(of: list) else {
            throw SharingError.ownerCannotLeave
        }

        if let shareRecordName = list.shareRecordID {
            let shareRecordID = CKRecord.ID(recordName: shareRecordName, zoneID: sharingZone.zoneID)
            try await container.privateCloudDatabase.deleteRecord(withID: shareRecordID)
        }

        // Clear sharing metadata
        list.isShared = false
        list.ownerID = nil
        list.shareRecordID = nil
        list.shareZoneOwnerName = nil
        list.lastSharedUpdatedAt = nil
        try? context.save()

        logger.info("Stopped sharing list '\(list.name)'")
    }

    // MARK: - Leave Shared List (Member)

    /// Member leaves a shared list. Removes the local copy.
    func leaveSharedList(_ list: ItemList, context: ModelContext) async throws {
        guard list.isShared else { throw SharingError.notShared }
        guard !UserIdentityService.shared.isCurrentUserOwner(of: list) else {
            throw SharingError.ownerCannotLeave
        }

        // Delete the local copy
        context.delete(list)
        try? context.save()

        logger.info("Left shared list '\(list.name)'")
    }

    // MARK: - Sharing Availability

    /// Whether CloudKit sharing is available on this device
    var isSharingAvailable: Bool {
        UserIdentityService.shared.isCloudKitAvailable
    }

    // MARK: - Zone Management

    private func ensureZoneExists() async throws {
        guard !zoneCreated else { return }

        do {
            _ = try await container.privateCloudDatabase.recordZone(for: sharingZone.zoneID)
            zoneCreated = true
        } catch let error as CKError where error.code == .zoneNotFound {
            _ = try await container.privateCloudDatabase.save(sharingZone)
            zoneCreated = true
        }
    }

    // MARK: - Detect Ended Sharing

    /// Checks if any shared lists the user was invited to have become unavailable.
    func checkForEndedSharing(in lists: [ItemList], context: ModelContext) async {
        await UserIdentityService.shared.ensureIdentityResolved()

        for list in lists where list.isShared {
            guard !UserIdentityService.shared.isCurrentUserOwner(of: list) else { continue }
            guard let zoneOwnerName = list.shareZoneOwnerName else { continue }

            let targetZoneID = CKRecordZone.ID(
                zoneName: sharingZone.zoneID.zoneName,
                ownerName: zoneOwnerName
            )
            let listRecordID = CKRecord.ID(
                recordName: "List-\(list.id.uuidString)",
                zoneID: targetZoneID
            )

            do {
                _ = try await container.sharedCloudDatabase.record(for: listRecordID)
            } catch let ckError as CKError {
                let revocationCodes: [CKError.Code] = [
                    .unknownItem, .zoneNotFound, .permissionFailure,
                    .userDeletedZone, .notAuthenticated
                ]
                if revocationCodes.contains(ckError.code) {
                    logger.notice("Shared list '\(list.name)' no longer available — converting to local")
                    convertToLocalCopy(list, context: context)
                }
            } catch {
                // Non-CKError: ignore
            }
        }
    }

    /// Converts a shared list to a local copy after sharing ended
    private func convertToLocalCopy(_ list: ItemList, context: ModelContext) {
        let name = list.name
        list.isShared = false
        list.ownerID = nil
        list.shareRecordID = nil
        list.shareZoneOwnerName = nil
        list.lastSharedUpdatedAt = nil
        try? context.save()

        NotificationCenter.default.post(
            name: SharingManager.sharingEndedNotification,
            object: nil,
            userInfo: ["listName": name]
        )
    }
}

// MARK: - Errors

enum SharingError: LocalizedError {
    case alreadyShared
    case notShared
    case cloudKitNotAvailable
    case shareNotFound
    case invalidShare
    case ownerCannotLeave

    var errorDescription: String? {
        switch self {
        case .alreadyShared: "This list is already shared."
        case .notShared: "This list is not shared."
        case .cloudKitNotAvailable: "iCloud is not available. Sign in to iCloud in Settings."
        case .shareNotFound: "Could not find the share. It may have been deleted."
        case .invalidShare: "The share data is invalid."
        case .ownerCannotLeave: "The owner cannot leave. Stop sharing instead."
        }
    }
}
