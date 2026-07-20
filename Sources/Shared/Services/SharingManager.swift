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

import CloudKit
import SwiftData
import OSLog

@Observable
@MainActor
final class SharingManager {
    static let shared = SharingManager()

    private let logger = Logger(subsystem: "ru.protos.sharebudget", category: "Sharing")

    /// Notification posted when a shared list becomes unavailable
    static let sharingEndedNotification = Notification.Name("SharingManager.sharingEnded")

    /// Notification posted when items have been synced from CloudKit.
    /// Views should re-sync using their own ModelContext when they receive this.
    static let itemsDidSyncNotification = Notification.Name("SharingManager.itemsDidSync")

    // MARK: - CloudKit Configuration

    private let container = CKContainer(identifier: AppConstants.cloudKitContainerID)

    /// CRITICAL: Sharing requires a custom zone. Default zone records cannot be shared.
    private let sharingZone = CKRecordZone(zoneName: "SharedLists")
    private var zoneCreated = false

    private let listRecordType = "SharedList"
    private let itemRecordType = "SharedListItem"

    /// Subscription IDs for CloudKit push notifications
    private let sharedDBSubscriptionID = "SharedListsSubscription"
    private let privateZoneSubscriptionID = "SharedListsZoneSubscription"

    private init() {}

    // MARK: - Share Creation

    /// Creates a CKShare for a list, or returns the existing one.
    /// This is called when the user taps "Share" on a list.
    func fetchOrCreateShare(
        for list: Account,
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

        // 7. Push existing items to CloudKit so members can see them
        do {
            try await pushAllItems(for: list)
        } catch {
            logger.error("Failed to push existing items: \(error)")
        }

        return (share, container)
    }

    /// Fetches an existing CKShare by its record name
    private func fetchExistingShare(recordName: String, for list: Account) async throws -> CKShare {
        let (database, zoneID) = try databaseAndZone(for: list)
        let shareRecordID = CKRecord.ID(recordName: recordName, zoneID: zoneID)

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
    ) async throws -> Account {
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

        guard let rootRecordID = metadata.hierarchicalRootRecordID else {
            throw SharingError.invalidShare
        }
        let zoneID = rootRecordID.zoneID

        // Даём серверу время материализовать зону в sharedCloudDatabase,
        // затем сканируем все записи зоны целиком (устойчивее к propagation delay,
        // чем прямой fetch по конкретному recordID)
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        let records = try await fetchAllRecordsWithRetry(in: zoneID)

        guard let record = records.first(where: { $0.recordID == rootRecordID }) else {
            throw SharingError.invalidShare
        }

        // Create or find the local ItemList
        let listID: UUID
        if let idString = record["listID"] as? String, let uuid = UUID(uuidString: idString) {
            listID = uuid
        } else {
            listID = UUID()
        }

        // Check if list already exists locally
        let descriptor = FetchDescriptor<Account>(predicate: #Predicate { $0.id == listID })
        if let existing = try? context.fetch(descriptor).first {
            logger.info("Share accepted — list '\(existing.name)' already exists locally")
            return existing
        }

        // Create new local list from the shared record
        let list = Account(
            id: listID,
            name: (record["name"] as? String) ?? "Shared List",
            icon: (record["icon"] as? String) ?? "list.bullet",
            colorHex: (record["colorHex"] as? String) ?? "007AFF"
        )
        list.isShared = true
        list.ownerID = metadata.ownerIdentity.userRecordID?.recordName
        list.shareRecordID = metadata.share.recordID.recordName
        list.shareZoneOwnerName = zoneID.ownerName
        list.isPro = true
        list.lastSharedUpdatedAt = Date()

        context.insert(list)
        DefaultCategories.seed(into: list, context: context)
        try? context.save()

        logger.info("Share accepted — created list '\(list.name)'")

        // Sync items from the owner
        try? await syncItems(for: list, context: context)

        return list
    }

    /// Сканирует все записи конкретной зоны в sharedCloudDatabase с повторными попытками,
    /// пока зона не станет доступна (или не истечёт лимит попыток)
    private func fetchAllRecordsWithRetry(
        in zoneID: CKRecordZone.ID,
        maxAttempts: Int = 6
    ) async throws -> [CKRecord] {
        var lastError: Error?

        for attempt in 1...maxAttempts {
            do {
                let records = try await fetchAllRecords(in: zoneID)

                if !records.isEmpty {
                    return records
                }

                let delaySeconds = Double(attempt) * 2   // 2с, 4с, 6с, 8с, 10с, 12с
                try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))

            } catch let error as CKError {
                lastError = error

                let retryableCodes: [CKError.Code] = [
                    .zoneNotFound, .unknownItem, .networkFailure,
                    .networkUnavailable, .serviceUnavailable,
                    .requestRateLimited, .serverResponseLost
                ]
                guard retryableCodes.contains(error.code) else {
                    throw error
                }

                let delaySeconds = Double(1 << (attempt - 1))
                try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            }
        }

        throw lastError ?? SharingError.invalidShare
    }


    // MARK: - Stop Sharing

    /// Owner stops sharing a list. Removes the CKShare.
    func stopSharing(_ list: Account, context: ModelContext) async throws {
        guard list.isShared else { throw SharingError.notShared }
        guard UserIdentityService.shared.isCurrentUserOwner(of: list) else {
            throw SharingError.ownerCannotLeave
        }

        if let shareRecordName = list.shareRecordID {
            let shareRecordID = CKRecord.ID(recordName: shareRecordName, zoneID: sharingZone.zoneID)
            try await container.privateCloudDatabase.deleteRecord(withID: shareRecordID)
        }
        
        try await deleteAllCloudRecords(for: list)

        // Clear sharing metadata
        list.isShared = false
        list.ownerID = nil
        list.shareRecordID = nil
        list.shareZoneOwnerName = nil
        list.lastSharedUpdatedAt = nil
        try? context.save()

        logger.info("Stopped sharing list '\(list.name)'")
    }
    
    /// Deletes all CloudKit records (list root + items) belonging to this account.
    /// Safe to call whether the account is currently shared or not.
    func deleteAllCloudRecords(for list: Account) async throws {
        let itemRecordIDs = (list.transactions ?? []).map {
            CKRecord.ID(recordName: "Item-\($0.id.uuidString)", zoneID: sharingZone.zoneID)
        }
        let listRecordID = CKRecord.ID(recordName: "List-\(list.id.uuidString)", zoneID: sharingZone.zoneID)

        let allIDsToDelete = itemRecordIDs + [listRecordID]

        guard !allIDsToDelete.isEmpty else { return }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: allIDsToDelete)
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            container.privateCloudDatabase.add(operation)
        }

        logger.info("Deleted \(allIDsToDelete.count) cloud record(s) for list '\(list.name)'")
    }


    // MARK: - Leave Shared List (Member)

    /// Member leaves a shared list. Removes the local copy.
    func leaveSharedList(_ list: Account, context: ModelContext) async throws {
        guard list.isShared else { throw SharingError.notShared }
        guard !UserIdentityService.shared.isCurrentUserOwner(of: list) else {
            throw SharingError.ownerCannotLeave
        }

        // Delete the local copy
        context.delete(list)
        try? context.save()

        logger.info("Left shared list '\(list.name)'")
    }

    // MARK: - Item Sync
    //
    // The CKShare only shares the root list record. Items must be synced
    // separately as individual CKRecords in the same shared zone.
    //
    // Owner  → reads/writes privateCloudDatabase
    // Member → reads/writes sharedCloudDatabase (with owner's zone ID)

    /// Resolves the correct database and zone for a shared list.
    /// Owner uses privateCloudDatabase + own zone.
    /// Member uses sharedCloudDatabase + owner's zone.
    private func databaseAndZone(for list: Account) throws -> (CKDatabase, CKRecordZone.ID) {
        let isOwner = UserIdentityService.shared.isCurrentUserOwner(of: list)

        let zoneID: CKRecordZone.ID
        if isOwner {
            zoneID = sharingZone.zoneID
        } else if let ownerName = list.shareZoneOwnerName {
            zoneID = CKRecordZone.ID(zoneName: sharingZone.zoneID.zoneName, ownerName: ownerName)
        } else {
            throw SharingError.invalidShare
        }

        let database = isOwner ? container.privateCloudDatabase : container.sharedCloudDatabase
        return (database, zoneID)
    }

    /// Converts a ListItem into a CKRecord linked to its parent list record.
    ///
    /// CRITICAL: The parent reference links the item to the shared list record.
    /// Without this, the item exists in the zone but is NOT part of the
    /// CKShare hierarchy — members won't be able to see it.
    private func makeItemRecord(
        for item: Transaction,
        listID: UUID,
        zoneID: CKRecordZone.ID
    ) -> CKRecord {
        let recordID = CKRecord.ID(recordName: "Item-\(item.id.uuidString)", zoneID: zoneID)
        let record = CKRecord(recordType: itemRecordType, recordID: recordID)
        record["itemID"] = item.id.uuidString as CKRecordValue
        record["listID"] = listID.uuidString as CKRecordValue
        record["title"] = item.title as CKRecordValue
        record["createdByUserID"] = (item.createdByUserID ?? "") as CKRecordValue
        record["createdByDisplayName"] = (item.createdByDisplayName ?? "") as CKRecordValue
        record["createdAt"] = item.createdAt as CKRecordValue
        record["modifiedAt"] = (item.modifiedAt ?? item.createdAt) as CKRecordValue
        record["amountMinorUnits"] = item.amountMinorUnits as CKRecordValue
        record["type"] = item.type.rawValue as CKRecordValue
        record["date"] = item.date as CKRecordValue
        record["paymentMethod"] = item.paymentMethod.rawValue as CKRecordValue

        if let note = item.note {
            record["note"] = note as CKRecordValue
        }

        if !item.tags.isEmpty {
            record["tags"] = item.tags as CKRecordValue
        }

        if let categoryID = item.category?.id {
            record["categoryID"] = categoryID.uuidString as CKRecordValue
        }

        let listRecordID = CKRecord.ID(recordName: "List-\(listID.uuidString)", zoneID: zoneID)
        record.parent = CKRecord.Reference(recordID: listRecordID, action: .none)
        return record
    }


    /// Pushes a single item to the shared CloudKit zone.
    /// Called after the user adds an item to a shared list.
    func pushItem(_ item: Transaction, for list: Account) async throws {
        guard list.isShared else { return }

        let (database, zoneID) = try databaseAndZone(for: list)
        let record = makeItemRecord(for: item, listID: list.id, zoneID: zoneID)

        _ = try await database.save(record)
        // Mark the item as confirmed in CloudKit so missing-remote checks
        // can distinguish "deleted remotely" from "not uploaded yet".
        item.modifiedAt = Date()
        try? item.modelContext?.save()
        logger.info("Pushed item '\(item.title)' to CloudKit")
    }

    /// Removes an item from the shared CloudKit zone.
    /// Called after the user deletes an item from a shared list.
    func removeItem(_ item: Transaction, for list: Account) async throws {
        guard list.isShared else { return }

        let (database, zoneID) = try databaseAndZone(for: list)
        let recordID = CKRecord.ID(recordName: "Item-\(item.id.uuidString)", zoneID: zoneID)

        do {
            try await database.deleteRecord(withID: recordID)
            logger.info("Removed item '\(item.title)' from CloudKit")
        } catch let error as CKError where error.code == .unknownItem {
            // Already deleted remotely — ignore
        }
    }

    /// Pushes all existing items for a list to CloudKit.
    /// Called when sharing is first created so pre-existing items are available to members.
    func pushAllItems(for list: Account) async throws {
        guard list.isShared else { return }

        let items = list.transactions ?? []
        guard !items.isEmpty else { return }

        let (database, zoneID) = try databaseAndZone(for: list)
        let records = items.map { makeItemRecord(for: $0, listID: list.id, zoneID: zoneID) }

        try await saveRecords(records, to: database)
        let syncedAt = Date()
        for item in items {
            item.modifiedAt = syncedAt
        }
        try? list.modelContext?.save()
        logger.info("Pushed \(records.count) items to CloudKit for list '\(list.name)'")
    }

    /// Fetches items from CloudKit and merges with local SwiftData.
    /// - Adds remote items that don't exist locally
    /// - Removes locally cached items that were previously synced but no longer exist remotely
    /// - Pushes local items that have never been confirmed in CloudKit yet
    func syncItems(for list: Account, context: ModelContext) async throws {
        guard list.isShared else { return }
        await UserIdentityService.shared.ensureIdentityResolved()

        let (database, zoneID) = try databaseAndZone(for: list)

        // Fetch all remote items for this list
        let predicate = NSPredicate(format: "listID == %@", list.id.uuidString)
        let query = CKQuery(recordType: itemRecordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        let (matchResults, _) = try await database.records(matching: query, inZoneWith: zoneID)

        // Build set of remote item IDs and their records
        var remoteItems: [UUID: CKRecord] = [:]
        for (recordID, result) in matchResults {
            switch result {
            case .success(let record):
                if let idString = record["itemID"] as? String, let uuid = UUID(uuidString: idString) {
                    remoteItems[uuid] = record
                }
            case .failure(let error):
                logger.error("Failed to fetch record \(recordID): \(error)")
            }
        }

        let localItems = list.transactions ?? []
        let localItemIDs = Set(localItems.map { $0.id })
        // 1. Add remote items that don't exist locally
        for (uuid, record) in remoteItems where !localItemIDs.contains(uuid) {
            let typeRaw = record["type"] as? String
            let type = typeRaw.flatMap(TransactionType.init(rawValue:)) ?? .expense

            let item = Transaction(
                id: uuid,
                title: (record["title"] as? String) ?? "",
                amountMinorUnits: (record["amountMinorUnits"] as? Int) ?? 0,
                type: type,
                date: (record["date"] as? Date) ?? Date(),
                createdByUserID: record["createdByUserID"] as? String
            )

            item.createdByDisplayName = record["createdByDisplayName"] as? String
            item.note = record["note"] as? String
            item.tags = (record["tags"] as? [String]) ?? []

            if let paymentRaw = record["paymentMethod"] as? String {
                item.paymentMethod = PaymentMethod(rawValue: paymentRaw) ?? .other
            }

            if let createdAt = record["createdAt"] as? Date {
                item.createdAt = createdAt
            }

            // Резолв категории по categoryID, если она уже есть локально
            if let categoryIDString = record["categoryID"] as? String,
               let categoryUUID = UUID(uuidString: categoryIDString) {
                item.category = list.categories?.first(where: { $0.id == categoryUUID })
            }

            // Presence in remote means this item is already synced.
            item.modifiedAt = Date()
            item.account = list
            context.insert(item)
            logger.debug("Synced remote item '\(item.title)' to local")
        }


        // Mark local items that we can see remotely as synced.
        for item in localItems where remoteItems.keys.contains(item.id) && item.modifiedAt == nil {
            item.modifiedAt = Date()
        }

        // 2. Remove local items that were synced before, but no longer exist remotely.
        // This prevents resurrecting items intentionally deleted by another participant.
        for item in localItems {
            let missingRemotely = !remoteItems.keys.contains(item.id)
            let wasPreviouslySynced = item.modifiedAt != nil
            if missingRemotely && wasPreviouslySynced {
                context.delete(item)
                logger.debug("Removed item '\(item.title)' (deleted remotely)")
            }
        }

        // 3. Push only items that haven't been confirmed in CloudKit yet.
        // Items that are missing remotely but were previously synced are treated
        // as remote deletions and are not re-uploaded.
        let itemsToPush = localItems.filter {
            !remoteItems.keys.contains($0.id) && $0.modifiedAt == nil
        }
        if !itemsToPush.isEmpty {
            let records = itemsToPush.map { makeItemRecord(for: $0, listID: list.id, zoneID: zoneID) }
            try await saveRecords(records, to: database)
            let syncedAt = Date()
            for item in itemsToPush {
                item.modifiedAt = syncedAt
            }
            logger.info("Pushed \(records.count) local items to CloudKit")
        }

        try? context.save()
        list.lastSharedUpdatedAt = Date()
        logger.info("Sync complete for '\(list.name)': \(remoteItems.count) remote, \(localItems.count) local")
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

    /// Batch-saves records using CKModifyRecordsOperation with `.changedKeys` policy.
    private func saveRecords(_ records: [CKRecord], to database: CKDatabase) async throws {
        let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
        operation.savePolicy = .changedKeys

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success: continuation.resume()
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
    }

    // MARK: - Detect Ended Sharing

    /// Checks if any shared lists the user was invited to have become unavailable.
    func checkForEndedSharing(in lists: [Account], context: ModelContext) async {
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

    // MARK: - CloudKit Subscriptions
    //
    // Two subscriptions ensure real-time sync via silent push notifications:
    //
    // 1. CKDatabaseSubscription on sharedCloudDatabase
    //    → Notifies MEMBERS when the owner (or other members) change items
    //
    // 2. CKRecordZoneSubscription on privateCloudDatabase (SharedLists zone)
    //    → Notifies the OWNER when members change items in the shared zone

    /// Registers CloudKit subscriptions for real-time sync.
    /// Called once on app launch after identity is resolved.
    func registerSubscriptions() async {
        guard isSharingAvailable else { return }

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true // Silent push

        // 1. Subscribe to shared database (for members receiving owner's changes)
        let sharedDBSub = CKDatabaseSubscription(subscriptionID: sharedDBSubscriptionID)
        sharedDBSub.notificationInfo = notificationInfo

        do {
            _ = try await container.sharedCloudDatabase.modifySubscriptions(
                saving: [sharedDBSub], deleting: []
            )
            logger.info("Registered shared database subscription")
        } catch let error as CKError where error.code == .serverRejectedRequest {
            // Already exists — fine
        } catch {
            logger.error("Failed to register shared DB subscription: \(error)")
        }

        // 2. Subscribe to the SharedLists zone (for owners receiving members' changes)
        do {
            try await ensureZoneExists()
            let zoneSub = CKRecordZoneSubscription(
                zoneID: sharingZone.zoneID,
                subscriptionID: privateZoneSubscriptionID
            )
            zoneSub.notificationInfo = notificationInfo

            _ = try await container.privateCloudDatabase.modifySubscriptions(
                saving: [zoneSub], deleting: []
            )
            logger.info("Registered private zone subscription")
        } catch let error as CKError where error.code == .serverRejectedRequest {
            // Already exists — fine
        } catch {
            logger.error("Failed to register zone subscription: \(error)")
        }
    }

    /// Handles a CloudKit remote notification by syncing all shared lists.
    /// Called from the app delegate's didReceiveRemoteNotification.
    func handleRemoteNotification(userInfo: [AnyHashable: Any]) async {
        let notification = CKNotification(fromRemoteNotificationDictionary: userInfo)
        guard notification is CKDatabaseNotification || notification is CKRecordZoneNotification else {
            return
        }

        logger.info("Received CloudKit push — syncing shared lists")

        let context = ModelContext(DataManager.shared.container)
        let descriptor = FetchDescriptor<Account>(predicate: #Predicate { $0.isShared == true })
        guard let lists = try? context.fetch(descriptor) else { return }

        for list in lists {
            do {
                try await syncItems(for: list, context: context)
            } catch {
                logger.error("Push sync failed for '\(list.name)': \(error)")
            }
        }

        // Notify views to refresh — SwiftData cross-context merge
        // may not trigger @Query updates for relationship predicates.
        NotificationCenter.default.post(name: SharingManager.itemsDidSyncNotification, object: nil)
    }

    /// Converts a shared list to a local copy after sharing ended
    private func convertToLocalCopy(_ list: Account, context: ModelContext) {
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

extension SharingManager {
    /// Сканирует sharedCloudDatabase на предмет доступных зон и синкает те, что ещё не отслеживаются локально
    func discoverSharedZones(context: ModelContext) async {
        do {
            let zoneIDs = try await fetchAllSharedZoneIDs()
            logger.info("Discovered \(zoneIDs.count) shared zone(s)")

            for zoneID in zoneIDs {
                if isZoneAlreadyTracked(zoneID, context: context) {
                    continue
                }
                await syncNewSharedZone(zoneID, context: context)
            }
        } catch {
            logger.error("Failed to discover shared zones: \(error)")
        }
    }

    private func fetchAllSharedZoneIDs() async throws -> [CKRecordZone.ID] {
        var zoneIDs: [CKRecordZone.ID] = []

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKFetchDatabaseChangesOperation(previousServerChangeToken: nil)

            operation.recordZoneWithIDChangedBlock = { zoneID in
                zoneIDs.append(zoneID)
            }

            operation.fetchDatabaseChangesResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            container.sharedCloudDatabase.add(operation)
        }

        return zoneIDs
    }

    private func isZoneAlreadyTracked(_ zoneID: CKRecordZone.ID, context: ModelContext) -> Bool {
        let ownerName = zoneID.ownerName
        let descriptor = FetchDescriptor<Account>(
            predicate: #Predicate { $0.shareZoneOwnerName == ownerName }
        )
        return (try? context.fetch(descriptor).first) != nil
    }

    private func syncNewSharedZone(_ zoneID: CKRecordZone.ID, context: ModelContext) async {
        do {
            let records = try await fetchAllRecords(in: zoneID)

            guard let rootRecord = records.first(where: { $0.recordType == listRecordType }) else {
                logger.info("Zone \(zoneID) has no root list record yet, skipping")
                return
            }

            let listID: UUID
            if let idString = rootRecord["listID"] as? String, let uuid = UUID(uuidString: idString) {
                listID = uuid
            } else {
                listID = UUID()
            }

            let descriptor = FetchDescriptor<Account>(predicate: #Predicate { $0.id == listID })
            if (try? context.fetch(descriptor).first) != nil {
                return
            }

            let list = Account(
                id: listID,
                name: (rootRecord["name"] as? String) ?? "Shared List",
                icon: (rootRecord["icon"] as? String) ?? "list.bullet",
                colorHex: (rootRecord["colorHex"] as? String) ?? "007AFF"
            )
            list.isShared = true
            list.shareZoneOwnerName = zoneID.ownerName
            list.lastSharedUpdatedAt = Date()

            context.insert(list)
            try? context.save()

            logger.info("Created list '\(list.name)' from discovered shared zone")

            try? await syncItems(for: list, context: context)
        } catch {
            logger.error("Failed to sync new shared zone \(zoneID): \(error)")
        }
    }

    private func fetchAllRecords(in zoneID: CKRecordZone.ID) async throws -> [CKRecord] {
        var records: [CKRecord] = []

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
            let operation = CKFetchRecordZoneChangesOperation(
                recordZoneIDs: [zoneID],
                configurationsByRecordZoneID: [zoneID: config]
            )

            operation.recordWasChangedBlock = { _, result in
                if case .success(let record) = result {
                    records.append(record)
                }
            }

            operation.fetchRecordZoneChangesResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            container.sharedCloudDatabase.add(operation)
        }

        return records
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
