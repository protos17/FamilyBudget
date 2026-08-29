import Testing
import SwiftData
@testable import iShareBudget

@MainActor
@Suite("AccountFormViewModel")
struct AccountFormViewModelTests {
    @Test("defaults for a new account")
    func newAccountDefaults() {
        let viewModel = AccountFormViewModel(editingAccount: nil, duplicateFrom: nil) { _ in }

        #expect(viewModel.name == "")
        #expect(viewModel.icon == "creditcard.fill")
        #expect(viewModel.colorHex == ColorPalette.all[0])
        #expect(viewModel.currencyCode == "RUB")
        #expect(viewModel.isEditing == false)
    }

    @Test("prefills fields when editing an existing account")
    func editingPrefill() {
        let account = MockData.makeAccount(name: "Отпуск", currencyCode: "USD", icon: "airplane", colorHex: "0984E3")
        let viewModel = AccountFormViewModel(editingAccount: account, duplicateFrom: nil) { _ in }

        #expect(viewModel.name == "Отпуск")
        #expect(viewModel.icon == "airplane")
        #expect(viewModel.colorHex == "0984E3")
        #expect(viewModel.currencyCode == "USD")
        #expect(viewModel.isEditing == true)
    }

    @Test("prefills icon/color/currency but not name when duplicating")
    func duplicatePrefill() {
        let source = MockData.makeAccount(name: "Основной", currencyCode: "EUR", icon: "house.fill", colorHex: "E67E22")
        let viewModel = AccountFormViewModel(editingAccount: nil, duplicateFrom: source) { _ in }

        #expect(viewModel.name == "")
        #expect(viewModel.icon == "house.fill")
        #expect(viewModel.colorHex == "E67E22")
        #expect(viewModel.currencyCode == "EUR")
    }

    @Test("navigationTitleText reflects editing / duplicating / creating")
    func navigationTitleStates() {
        let editing = AccountFormViewModel(editingAccount: MockData.makeAccount(), duplicateFrom: nil) { _ in }
        let duplicating = AccountFormViewModel(editingAccount: nil, duplicateFrom: MockData.makeAccount()) { _ in }
        let creating = AccountFormViewModel(editingAccount: nil, duplicateFrom: nil) { _ in }

        #expect(editing.navigationTitleText == "Редактировать бюджет")
        #expect(duplicating.navigationTitleText == "Копия бюджета")
        #expect(creating.navigationTitleText == "Новый бюджет")
    }

    @Test("canSave requires a non-blank name")
    func canSaveValidation() {
        let viewModel = AccountFormViewModel(editingAccount: nil, duplicateFrom: nil) { _ in }

        viewModel.name = "   "
        #expect(viewModel.canSave == false)

        viewModel.name = "Дом"
        #expect(viewModel.canSave == true)
    }

    @Test("save without attach(context:) does nothing")
    func saveWithoutContext() {
        var saved: Account?
        let viewModel = AccountFormViewModel(editingAccount: nil, duplicateFrom: nil) { saved = $0 }
        viewModel.name = "Дом"

        viewModel.save()

        #expect(saved == nil)
    }

    @Test("save creates a new account seeded with default categories")
    func saveCreatesAccount() throws {
        let context = try TestModelContainer.makeContext()
        var saved: Account?
        let viewModel = AccountFormViewModel(editingAccount: nil, duplicateFrom: nil) { saved = $0 }
        viewModel.attach(context: context)
        viewModel.name = "  Дом  "

        viewModel.save()

        let account = try #require(saved)
        #expect(account.name == "Дом")
        #expect(account.categories?.count == DefaultCategories.all.count)
    }

    @Test("save mutates the existing account when editing")
    func saveEditsAccount() throws {
        let context = try TestModelContainer.makeContext()
        let account = MockData.makeAccount(name: "Старое имя")
        context.insert(account)

        var saved: Account?
        let viewModel = AccountFormViewModel(editingAccount: account, duplicateFrom: nil) { saved = $0 }
        viewModel.attach(context: context)
        viewModel.name = "Новое имя"

        viewModel.save()

        #expect(saved?.id == account.id)
        #expect(account.name == "Новое имя")
    }

    @Test("save duplicates categories and transactions with new identities, leaving the source untouched")
    func saveDuplicatesContents() throws {
        let context = try TestModelContainer.makeContext()
        let source = MockData.makePopulatedAccount(in: context)
        let identity = MockUserIdentityService()
        identity.currentUserID = "duplicating-user"

        var saved: Account?
        let viewModel = AccountFormViewModel(
            editingAccount: nil,
            duplicateFrom: source.account,
            identity: identity
        ) { saved = $0 }
        viewModel.attach(context: context)
        viewModel.name = "Копия"

        viewModel.save()

        let newAccount = try #require(saved)
        #expect(newAccount.categories?.count == source.account.categories?.count)
        let newCategoryIDs = Set((newAccount.categories ?? []).map(\.id))
        let sourceCategoryIDs = Set((source.account.categories ?? []).map(\.id))
        #expect(newCategoryIDs.isDisjoint(with: sourceCategoryIDs))

        #expect(newAccount.transactions?.count == source.transactions.count)
        for transaction in newAccount.transactions ?? [] {
            #expect(transaction.createdByUserID == "duplicating-user")
            if let category = transaction.category {
                #expect(newCategoryIDs.contains(category.id))
            }
        }

        // Source is untouched
        #expect(source.account.categories?.count == 3)
        #expect(source.account.transactions?.count == source.transactions.count)
    }
}
