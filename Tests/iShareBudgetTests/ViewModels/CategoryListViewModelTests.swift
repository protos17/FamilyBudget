import Testing
import SwiftData
@testable import iShareBudget

@MainActor
@Suite("CategoryListViewModel")
struct CategoryListViewModelTests {
    @Test("categories mirrors account.sortedCategories order")
    func categoriesOrder() throws {
        let context = try TestModelContainer.makeContext()
        let populated = MockData.makePopulatedAccount(in: context)
        let viewModel = CategoryListViewModel(account: populated.account)

        #expect(viewModel.categories.map(\.name) == populated.account.sortedCategories.map(\.name))
    }

    @Test("deleteCategory without attach(context:) does nothing")
    func deleteWithoutContext() throws {
        let context = try TestModelContainer.makeContext()
        let populated = MockData.makePopulatedAccount(in: context)
        let viewModel = CategoryListViewModel(account: populated.account)

        viewModel.deleteCategory(populated.expenseCategory)

        #expect(populated.account.categories?.contains(where: { $0.id == populated.expenseCategory.id }) == true)
    }

    @Test("deleteCategory removes the category from the context")
    func deleteWithContext() async throws {
        let context = try TestModelContainer.makeContext()
        let populated = MockData.makePopulatedAccount(in: context)
        let viewModel = CategoryListViewModel(account: populated.account)
        viewModel.attach(context: context)

        viewModel.deleteCategory(populated.expenseCategory)

        await waitUntil {
            let remaining = try? context.fetch(FetchDescriptor<Category>())
            return remaining?.contains(where: { $0.id == populated.expenseCategory.id }) == false
        }
    }
}
