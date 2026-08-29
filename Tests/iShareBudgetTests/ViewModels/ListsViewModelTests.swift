import Testing
import Foundation
import SwiftData
@testable import iShareBudget

@MainActor
@Suite("ListsViewModel")
struct ListsViewModelTests {
    @Test("addList sets the sort order and persists")
    func addListSetsSortOrder() throws {
        let context = try TestModelContainer.makeContext()
        let account = MockData.makeAccount()
        context.insert(account)
        let viewModel = ListsViewModel()
        viewModel.attach(context: context)

        viewModel.addList(sortOrder: 3, newAccount: account)

        #expect(account.sortOrder == 3)
    }

    @Test("addList without attach(context:) does nothing")
    func addListWithoutContext() {
        let account = MockData.makeAccount()
        let viewModel = ListsViewModel()

        viewModel.addList(sortOrder: 3, newAccount: account)

        #expect(account.sortOrder == 0)
    }

    @Test("deleteAccount removes a non-shared account immediately")
    func deleteNonSharedAccount() throws {
        let context = try TestModelContainer.makeContext()
        let account = MockData.makeAccount(isShared: false)
        context.insert(account)
        let viewModel = ListsViewModel()
        viewModel.attach(context: context)

        viewModel.deleteAccount(account)

        let remaining = try context.fetch(FetchDescriptor<Account>())
        #expect(remaining.isEmpty)
    }

    @Test("deleteAccount stops sharing before deleting a shared account")
    func deleteSharedAccountSuccess() async throws {
        let context = try TestModelContainer.makeContext()
        let account = MockData.makeSharedAccount()
        context.insert(account)
        let sharing = MockSharingService()
        let viewModel = ListsViewModel(sharing: sharing)
        viewModel.attach(context: context)

        viewModel.deleteAccount(account)

        await waitUntil {
            let remaining = try? context.fetch(FetchDescriptor<Account>())
            return remaining?.isEmpty == true
        }
        #expect(sharing.stoppedLists.map(\.id) == [account.id])
    }

    @Test("deleteAccount surfaces an error and keeps the account when stopSharing fails")
    func deleteSharedAccountFailure() async throws {
        struct SomeError: Error, LocalizedError {
            var errorDescription: String? { "network down" }
        }
        let context = try TestModelContainer.makeContext()
        let account = MockData.makeSharedAccount()
        context.insert(account)
        let sharing = MockSharingService()
        sharing.errorToThrow = SomeError()
        let viewModel = ListsViewModel(sharing: sharing)
        viewModel.attach(context: context)

        viewModel.deleteAccount(account)

        await waitUntil { viewModel.showingDeletionError == true }
        #expect(viewModel.deletionErrorMessage.contains("network down"))
        let remaining = try context.fetch(FetchDescriptor<Account>())
        #expect(remaining.map(\.id) == [account.id])
    }

    @Test("leaveAccount delegates to the sharing service")
    func leaveAccountDelegates() async throws {
        let context = try TestModelContainer.makeContext()
        let account = MockData.makeSharedAccount()
        let sharing = MockSharingService()
        let viewModel = ListsViewModel(sharing: sharing)
        viewModel.attach(context: context)

        viewModel.leaveAccount(account)

        await waitUntil { sharing.leftLists.count == 1 }
        #expect(sharing.leftLists.map(\.id) == [account.id])
    }

    @Test("handleSharingEndedNotification extracts the list name when present")
    func handleSharingEndedNotificationWithName() {
        let viewModel = ListsViewModel()
        let notification = Notification(name: .init("test"), object: nil, userInfo: ["listName": "Общий бюджет"])

        viewModel.handleSharingEndedNotification(notification)

        #expect(viewModel.sharingEndedName == "Общий бюджет")
    }

    @Test("handleSharingEndedNotification ignores notifications without a list name")
    func handleSharingEndedNotificationWithoutName() {
        let viewModel = ListsViewModel()
        let notification = Notification(name: .init("test"), object: nil, userInfo: [:])

        viewModel.handleSharingEndedNotification(notification)

        #expect(viewModel.sharingEndedName == nil)
    }

    @Test("checkForEndedSharing skips the call when there are no shared lists")
    func checkForEndedSharingNoSharedLists() async throws {
        let context = try TestModelContainer.makeContext()
        let sharing = MockSharingService()
        let viewModel = ListsViewModel(sharing: sharing)
        viewModel.attach(context: context)

        await viewModel.checkForEndedSharing(in: [MockData.makeAccount(isShared: false)])

        #expect(sharing.endedSharingChecks.isEmpty)
    }

    @Test("checkForEndedSharing only passes the shared lists")
    func checkForEndedSharingFiltersShared() async throws {
        let context = try TestModelContainer.makeContext()
        let sharing = MockSharingService()
        let viewModel = ListsViewModel(sharing: sharing)
        viewModel.attach(context: context)
        let sharedAccount = MockData.makeSharedAccount()
        let localAccount = MockData.makeAccount(isShared: false)

        await viewModel.checkForEndedSharing(in: [sharedAccount, localAccount])

        #expect(sharing.endedSharingChecks.count == 1)
        #expect(sharing.endedSharingChecks.first?.map(\.id) == [sharedAccount.id])
    }

    @Test("refreshSharedZones without attach(context:) does nothing")
    func refreshSharedZonesWithoutContext() async {
        let sharing = MockSharingService()
        let viewModel = ListsViewModel(sharing: sharing)

        await viewModel.refreshSharedZones()

        #expect(sharing.discoverCallCount == 0)
    }

    @Test("refreshSharedZones delegates to the sharing service")
    func refreshSharedZonesWithContext() async throws {
        let context = try TestModelContainer.makeContext()
        let sharing = MockSharingService()
        let viewModel = ListsViewModel(sharing: sharing)
        viewModel.attach(context: context)

        await viewModel.refreshSharedZones()

        #expect(sharing.discoverCallCount == 1)
    }
}
