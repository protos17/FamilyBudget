import Foundation
import CloudKit
import SwiftData
@testable import iShareBudget

@MainActor
final class MockSharingService: SharingProviding {
    var isSharingAvailable = true
    var shareToReturn: CKShare?
    var containerToReturn: CKContainer?
    var accountToReturn: Account?
    var errorToThrow: Error?

    private(set) var fetchOrCreateShareCallCount = 0
    private(set) var acceptedMetadata: [CKShare.Metadata] = []
    private(set) var pushedItems: [Transaction] = []
    private(set) var removedItems: [Transaction] = []
    private(set) var syncedLists: [Account] = []
    private(set) var stoppedLists: [Account] = []
    private(set) var leftLists: [Account] = []
    private(set) var discoverCallCount = 0
    private(set) var endedSharingChecks: [[Account]] = []

    func fetchOrCreateShare(for list: Account, context: ModelContext) async throws -> (CKShare, CKContainer) {
        fetchOrCreateShareCallCount += 1
        if let errorToThrow { throw errorToThrow }
        let container = containerToReturn ?? CKContainer(identifier: "iCloud.ru.protos.sharebudget")
        let share = shareToReturn ?? CKShare(recordZoneID: CKRecordZone.ID(zoneName: "SharedLists"))
        return (share, container)
    }

    func acceptShare(_ metadata: CKShare.Metadata, context: ModelContext) async throws -> Account {
        acceptedMetadata.append(metadata)
        if let errorToThrow { throw errorToThrow }
        return accountToReturn ?? MockData.makeAccount()
    }

    func stopSharing(_ list: Account, context: ModelContext) async throws {
        if let errorToThrow { throw errorToThrow }
        stoppedLists.append(list)
    }

    func leaveSharedList(_ list: Account, context: ModelContext) async throws {
        if let errorToThrow { throw errorToThrow }
        leftLists.append(list)
    }

    func pushItem(_ item: Transaction, for list: Account) async throws {
        if let errorToThrow { throw errorToThrow }
        pushedItems.append(item)
    }

    func removeItem(_ item: Transaction, for list: Account) async throws {
        if let errorToThrow { throw errorToThrow }
        removedItems.append(item)
    }

    func syncItems(for list: Account, context: ModelContext) async throws {
        if let errorToThrow { throw errorToThrow }
        syncedLists.append(list)
    }

    func checkForEndedSharing(in lists: [Account], context: ModelContext) async {
        endedSharingChecks.append(lists)
    }

    func discoverSharedZones(context: ModelContext) async {
        discoverCallCount += 1
    }
}
