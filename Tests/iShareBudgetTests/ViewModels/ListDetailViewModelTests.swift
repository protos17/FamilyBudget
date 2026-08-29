import Testing
import Foundation
import SwiftData
import CloudKit
@testable import iShareBudget

@MainActor
@Suite("ListDetailViewModel")
struct ListDetailViewModelTests {
    // MARK: - Filtering

    @Test("filteredItems keeps only transactions from the selected month")
    func filterByMonth() throws {
        let context = try TestModelContainer.makeContext()
        let populated = MockData.makePopulatedAccount(in: context)
        let viewModel = ListDetailViewModel(list: populated.account)
        viewModel.selectedMonth = Date.now

        let result = viewModel.filteredItems(from: populated.transactions)

        #expect(result.count == 3)
        #expect(!result.contains { $0.title == "Прошлый месяц" })
    }

    @Test("filteredItems narrows by selected category")
    func filterByCategory() throws {
        let context = try TestModelContainer.makeContext()
        let populated = MockData.makePopulatedAccount(in: context)
        let viewModel = ListDetailViewModel(list: populated.account)
        viewModel.selectedMonth = Date.now
        viewModel.selectedCategory = populated.incomeCategory

        let result = viewModel.filteredItems(from: populated.transactions)

        #expect(result.map(\.title) == ["Зарплата"])
    }

    @Test("filteredItems narrows by selected type")
    func filterByType() throws {
        let context = try TestModelContainer.makeContext()
        let populated = MockData.makePopulatedAccount(in: context)
        let viewModel = ListDetailViewModel(list: populated.account)
        viewModel.selectedMonth = Date.now
        viewModel.selectedType = .expense

        let result = viewModel.filteredItems(from: populated.transactions)

        #expect(Set(result.map(\.title)) == ["Обед", "Такси"])
    }

    @Test("filteredItems combines month, category and type filters")
    func filterCombination() throws {
        let context = try TestModelContainer.makeContext()
        let populated = MockData.makePopulatedAccount(in: context)
        let viewModel = ListDetailViewModel(list: populated.account)
        viewModel.selectedMonth = Date.now
        viewModel.selectedCategory = populated.expenseCategory
        viewModel.selectedType = .expense

        let result = viewModel.filteredItems(from: populated.transactions)

        #expect(Set(result.map(\.title)) == ["Обед", "Такси"])
    }

    // MARK: - Summary

    @Test("summary sums income and expense separately")
    func summaryTotals() {
        let account = MockData.makeAccount()
        let viewModel = ListDetailViewModel(list: account)
        let items = [
            MockData.makeTransaction(minorUnits: 10000, type: .expense),
            MockData.makeTransaction(minorUnits: 5000, type: .expense),
            MockData.makeTransaction(minorUnits: 200000, type: .income)
        ]

        let result = viewModel.summary(for: items)

        #expect(result.expense == 150)
        #expect(result.income == 2000)
    }

    @Test("summary of an empty list is zero")
    func summaryEmpty() {
        let account = MockData.makeAccount()
        let viewModel = ListDetailViewModel(list: account)

        let result = viewModel.summary(for: [])

        #expect(result.income == 0)
        #expect(result.expense == 0)
    }

    // MARK: - Breakdown

    @Test("breakdownSlices sorts by amount descending and sums to 100%")
    func breakdownSorting() {
        let account = MockData.makeAccount()
        let groceries = MockData.makeCategory(name: "Продукты", kind: .expense)
        let transport = MockData.makeCategory(name: "Транспорт", kind: .expense)
        let viewModel = ListDetailViewModel(list: account)
        let items = [
            MockData.makeTransaction(minorUnits: 30000, type: .expense, category: transport),
            MockData.makeTransaction(minorUnits: 50000, type: .expense, category: groceries),
            MockData.makeTransaction(minorUnits: 20000, type: .expense, category: groceries)
        ]

        let slices = viewModel.breakdownSlices(for: items)

        // groceries totals 700, transport totals 300 -> groceries first
        #expect(slices.map(\.categoryName) == ["Продукты", "Транспорт"])
        #expect(slices.map(\.amount) == [700, 300])
        let totalPercentage = slices.reduce(0) { $0 + $1.percentage }
        #expect(abs(totalPercentage - 100) < 0.001)
    }

    @Test("breakdownSlices excludes income and transactions without a category")
    func breakdownExcludesIncomeAndUncategorized() {
        let account = MockData.makeAccount()
        let category = MockData.makeCategory(name: "Продукты", kind: .expense)
        let viewModel = ListDetailViewModel(list: account)
        let items = [
            MockData.makeTransaction(title: "Категоризировано", minorUnits: 10000, type: .expense, category: category),
            MockData.makeTransaction(title: "Без категории", minorUnits: 5000, type: .expense, category: nil),
            MockData.makeTransaction(title: "Доход", minorUnits: 100000, type: .income, category: category)
        ]

        let slices = viewModel.breakdownSlices(for: items)

        #expect(slices.count == 1)
        #expect(slices.first?.categoryName == "Продукты")
        #expect(slices.first?.amount == 100)
    }

    @Test("breakdownSlices is empty when there are no expenses")
    func breakdownEmptyWhenNoExpenses() {
        let account = MockData.makeAccount()
        let viewModel = ListDetailViewModel(list: account)
        let items = [MockData.makeTransaction(minorUnits: 100000, type: .income)]

        #expect(viewModel.breakdownSlices(for: items).isEmpty)
    }

    // MARK: - Present actions

    @Test("presentAddTransaction(type:) clears editing state and opens the sheet")
    func presentAddTransaction() {
        let account = MockData.makeAccount()
        let viewModel = ListDetailViewModel(list: account)
        viewModel.editingTransaction = MockData.makeTransaction()
        viewModel.recognizedPrefillData = MockData.makeRecognizedData()

        viewModel.presentAddTransaction(type: .income)

        #expect(viewModel.editingTransaction == nil)
        #expect(viewModel.recognizedPrefillData == nil)
        #expect(viewModel.prefilledType == .income)
        #expect(viewModel.showingAddTransaction == true)
    }

    @Test("presentEditTransaction targets the given item and clears recognized data")
    func presentEditTransaction() {
        let account = MockData.makeAccount()
        let viewModel = ListDetailViewModel(list: account)
        viewModel.recognizedPrefillData = MockData.makeRecognizedData()
        let item = MockData.makeTransaction(type: .income)

        viewModel.presentEditTransaction(item)

        #expect(viewModel.editingTransaction?.id == item.id)
        #expect(viewModel.recognizedPrefillData == nil)
        #expect(viewModel.prefilledType == .income)
        #expect(viewModel.showingAddTransaction == true)
    }

    @Test("presentAddTransaction(recognized:) stores the recognized data and clears editing state")
    func presentAddTransactionRecognized() {
        let account = MockData.makeAccount()
        let viewModel = ListDetailViewModel(list: account)
        viewModel.editingTransaction = MockData.makeTransaction()
        let recognized = MockData.makeRecognizedData(title: "Такси")

        viewModel.presentAddTransaction(recognized: recognized)

        #expect(viewModel.editingTransaction == nil)
        #expect(viewModel.recognizedPrefillData?.title == "Такси")
        #expect(viewModel.prefilledType == .expense)
        #expect(viewModel.showingAddTransaction == true)
    }

    @Test("presentCreateCategory records the kind and opens the sheet")
    func presentCreateCategory() {
        let account = MockData.makeAccount()
        let viewModel = ListDetailViewModel(list: account)

        viewModel.presentCreateCategory(kind: .income)

        #expect(viewModel.categoryCreationKind == .income)
        #expect(viewModel.showingCreateCategory == true)
    }

    // MARK: - Banner

    @Test("bannerText reflects ownership")
    func bannerTextOwnership() {
        let account = MockData.makeAccount()
        let owner = MockUserIdentityService()
        owner.ownerResult = true
        let invited = MockUserIdentityService()
        invited.ownerResult = false

        #expect(ListDetailViewModel(list: account, identity: owner).bannerText == "Вы делитесь этим бюджетом")
        #expect(ListDetailViewModel(list: account, identity: invited).bannerText == "Доступно вам по приглашению")
    }

    // MARK: - Sharing

    @Test("presentSharing surfaces an error immediately when iCloud is unavailable")
    func presentSharingUnavailable() throws {
        let context = try TestModelContainer.makeContext()
        let account = MockData.makeAccount()
        let sharing = MockSharingService()
        sharing.isSharingAvailable = false
        let viewModel = ListDetailViewModel(list: account, sharing: sharing)
        viewModel.attach(context: context)

        viewModel.presentSharing()

        #expect(viewModel.showingError == true)
        #expect(viewModel.showingShareSheet == false)
        #expect(sharing.fetchOrCreateShareCallCount == 0)
    }

    @Test("presentSharing populates the share sheet on success")
    func presentSharingSuccess() async throws {
        let context = try TestModelContainer.makeContext()
        let account = MockData.makeAccount()
        let sharing = MockSharingService()
        let viewModel = ListDetailViewModel(list: account, sharing: sharing)
        viewModel.attach(context: context)

        viewModel.presentSharing()

        await waitUntil { viewModel.showingShareSheet == true }
        #expect(viewModel.activeShare != nil)
        #expect(viewModel.activeContainer != nil)
    }

    @Test("presentSharing surfaces the error message on failure")
    func presentSharingFailure() async throws {
        struct SomeError: Error, LocalizedError {
            var errorDescription: String? { "no network" }
        }
        let context = try TestModelContainer.makeContext()
        let account = MockData.makeAccount()
        let sharing = MockSharingService()
        sharing.errorToThrow = SomeError()
        let viewModel = ListDetailViewModel(list: account, sharing: sharing)
        viewModel.attach(context: context)

        viewModel.presentSharing()

        await waitUntil { viewModel.showingError == true }
        #expect(viewModel.errorMessage.contains("no network"))
    }

    // MARK: - Save / delete

    @Test("saveNewItem inserts locally and skips pushing when the list is not shared")
    func saveNewItemNotShared() throws {
        let context = try TestModelContainer.makeContext()
        let account = MockData.makeAccount(isShared: false)
        context.insert(account)
        let sharing = MockSharingService()
        let viewModel = ListDetailViewModel(list: account, sharing: sharing)
        viewModel.attach(context: context)
        let item = MockData.makeTransaction()

        viewModel.saveNewItem(item)

        #expect(item.account?.id == account.id)
        #expect(sharing.pushedItems.isEmpty)
    }

    @Test("saveNewItem pushes the item when the list is shared")
    func saveNewItemShared() async throws {
        let context = try TestModelContainer.makeContext()
        let account = MockData.makeSharedAccount()
        context.insert(account)
        let sharing = MockSharingService()
        let viewModel = ListDetailViewModel(list: account, sharing: sharing)
        viewModel.attach(context: context)
        let item = MockData.makeTransaction()

        viewModel.saveNewItem(item)

        await waitUntil { sharing.pushedItems.count == 1 }
        #expect(sharing.pushedItems.first?.id == item.id)
    }

    @Test("saveEditedItem pushes the currently-editing item when shared")
    func saveEditedItemShared() async throws {
        let context = try TestModelContainer.makeContext()
        let account = MockData.makeSharedAccount()
        let item = MockData.makeTransaction()
        item.account = account
        context.insert(account)
        context.insert(item)
        let sharing = MockSharingService()
        let viewModel = ListDetailViewModel(list: account, sharing: sharing)
        viewModel.attach(context: context)
        viewModel.editingTransaction = item

        viewModel.saveEditedItem()

        await waitUntil { sharing.pushedItems.count == 1 }
        #expect(sharing.pushedItems.first?.id == item.id)
    }

    @Test("saveEditedItem does not push when the list is not shared")
    func saveEditedItemNotShared() throws {
        let context = try TestModelContainer.makeContext()
        let account = MockData.makeAccount(isShared: false)
        let item = MockData.makeTransaction()
        item.account = account
        context.insert(account)
        context.insert(item)
        let sharing = MockSharingService()
        let viewModel = ListDetailViewModel(list: account, sharing: sharing)
        viewModel.attach(context: context)
        viewModel.editingTransaction = item

        viewModel.saveEditedItem()

        #expect(sharing.pushedItems.isEmpty)
    }

    @Test("deleteItem removes locally and pushes removal when shared")
    func deleteItemShared() async throws {
        let context = try TestModelContainer.makeContext()
        let account = MockData.makeSharedAccount()
        let item = MockData.makeTransaction()
        item.account = account
        context.insert(account)
        context.insert(item)
        let sharing = MockSharingService()
        let viewModel = ListDetailViewModel(list: account, sharing: sharing)
        viewModel.attach(context: context)

        viewModel.deleteItem(item)

        let remaining = try context.fetch(FetchDescriptor<Transaction>())
        #expect(remaining.isEmpty)
        await waitUntil { sharing.removedItems.count == 1 }
    }

    @Test("deleteItem does not push removal when the list is not shared")
    func deleteItemNotShared() throws {
        let context = try TestModelContainer.makeContext()
        let account = MockData.makeAccount(isShared: false)
        let item = MockData.makeTransaction()
        item.account = account
        context.insert(account)
        context.insert(item)
        let sharing = MockSharingService()
        let viewModel = ListDetailViewModel(list: account, sharing: sharing)
        viewModel.attach(context: context)

        viewModel.deleteItem(item)

        #expect(sharing.removedItems.isEmpty)
    }

    @Test("leaveList delegates to the sharing service")
    func leaveListDelegates() async throws {
        let context = try TestModelContainer.makeContext()
        let account = MockData.makeSharedAccount()
        let sharing = MockSharingService()
        let viewModel = ListDetailViewModel(list: account, sharing: sharing)
        viewModel.attach(context: context)

        viewModel.leaveList()

        await waitUntil { sharing.leftLists.count == 1 }
        #expect(sharing.leftLists.first?.id == account.id)
    }

    // MARK: - Sync

    @Test("syncSharedItems is a no-op for a non-shared list")
    func syncSkippedWhenNotShared() async throws {
        let context = try TestModelContainer.makeContext()
        let account = MockData.makeAccount(isShared: false)
        let sharing = MockSharingService()
        let viewModel = ListDetailViewModel(list: account, sharing: sharing)
        viewModel.attach(context: context)

        await viewModel.syncSharedItems()

        #expect(sharing.syncedLists.isEmpty)
    }

    @Test("syncSharedItems is a no-op while the add-transaction sheet is open")
    func syncSkippedWhileAddingTransaction() async throws {
        let context = try TestModelContainer.makeContext()
        let account = MockData.makeSharedAccount()
        let sharing = MockSharingService()
        let viewModel = ListDetailViewModel(list: account, sharing: sharing)
        viewModel.attach(context: context)
        viewModel.showingAddTransaction = true

        await viewModel.syncSharedItems()

        #expect(sharing.syncedLists.isEmpty)
    }

    @Test("syncSharedItems syncs a shared list and resets isSyncing")
    func syncSharedListSucceeds() async throws {
        let context = try TestModelContainer.makeContext()
        let account = MockData.makeSharedAccount()
        let sharing = MockSharingService()
        let viewModel = ListDetailViewModel(list: account, sharing: sharing)
        viewModel.attach(context: context)

        await viewModel.syncSharedItems()

        #expect(sharing.syncedLists.map(\.id) == [account.id])
        #expect(viewModel.isSyncing == false)
    }

    @Test("syncSharedItems surfaces an error on failure")
    func syncSharedListFailure() async throws {
        struct SomeError: Error, LocalizedError {
            var errorDescription: String? { "sync failed" }
        }
        let context = try TestModelContainer.makeContext()
        let account = MockData.makeSharedAccount()
        let sharing = MockSharingService()
        sharing.errorToThrow = SomeError()
        let viewModel = ListDetailViewModel(list: account, sharing: sharing)
        viewModel.attach(context: context)

        await viewModel.syncSharedItems()

        #expect(viewModel.showingError == true)
        #expect(viewModel.errorMessage.contains("sync failed"))
    }

    // MARK: - Calendar helper

    @Test("Calendar.startOfMonth(for:) truncates to the first of the month")
    func startOfMonthHelper() {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 15
        components.hour = 12
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: components)!

        let startOfMonth = calendar.startOfMonth(for: date)
        let resultComponents = calendar.dateComponents([.year, .month, .day, .hour], from: startOfMonth)

        #expect(resultComponents.year == 2026)
        #expect(resultComponents.month == 3)
        #expect(resultComponents.day == 1)
        #expect((resultComponents.hour ?? 0) == 0)
    }
}
