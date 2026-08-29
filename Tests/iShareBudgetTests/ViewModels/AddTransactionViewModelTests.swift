import Testing
import SwiftData
@testable import iShareBudget

@MainActor
@Suite("AddTransactionViewModel")
struct AddTransactionViewModelTests {
    @Test("defaults for a brand new transaction")
    func newTransactionDefaults() {
        let account = MockData.makeAccount()
        let viewModel = AddTransactionViewModel(
            account: account, prefilledType: .expense, editingTransaction: nil,
            onSaveNew: { _ in }, onSaveEdit: {}
        )

        #expect(viewModel.type == .expense)
        #expect(viewModel.title == "")
        #expect(viewModel.amountText == "")
        #expect(viewModel.selectedCategory == nil)
        #expect(viewModel.note == "")
        #expect(viewModel.paymentMethod == .card)
        #expect(viewModel.isEditing == false)
    }

    @Test("prefills fields when editing an existing transaction")
    func editingPrefill() throws {
        let context = try TestModelContainer.makeContext()
        let category = MockData.makeCategory(name: "Такси")
        let transaction = MockData.makeTransaction(
            title: "Поездка", minorUnits: 45000, type: .expense, category: category,
            paymentMethod: .cash, note: "Вечер"
        )
        let account = MockData.makeAccount()
        account.categories = [category]
        context.insert(account)
        context.insert(transaction)

        let viewModel = AddTransactionViewModel(
            account: account, prefilledType: .income, editingTransaction: transaction,
            onSaveNew: { _ in }, onSaveEdit: {}
        )

        #expect(viewModel.type == .expense)
        #expect(viewModel.title == "Поездка")
        #expect(viewModel.amountText == "450")
        #expect(viewModel.selectedCategory?.id == category.id)
        #expect(viewModel.note == "Вечер")
        #expect(viewModel.paymentMethod == .cash)
        #expect(viewModel.isEditing == true)
    }

    @Test("prefills fields from recognized receipt data, matching the category by name")
    func recognizedDataPrefill() {
        let account = MockData.makeAccount()
        let category = MockData.makeCategory(name: "Продукты")
        account.categories = [category]
        let recognized = MockData.makeRecognizedData(
            title: "Пятёрочка", amount: 1234.5, categoryName: "продукты", paymentMethod: "cash", date: "15-03-2026"
        )

        let viewModel = AddTransactionViewModel(
            account: account, prefilledType: .expense, editingTransaction: nil, recognizedData: recognized,
            onSaveNew: { _ in }, onSaveEdit: {}
        )

        #expect(viewModel.title == "Пятёрочка")
        #expect(viewModel.amountText == "1234.5")
        #expect(viewModel.selectedCategory?.id == category.id)
        #expect(viewModel.paymentMethod == .cash)
    }

    @Test("recognized data with an unmatched category name and invalid payment method falls back gracefully")
    func recognizedDataFallbacks() {
        let account = MockData.makeAccount()
        account.categories = [MockData.makeCategory(name: "Продукты")]
        let recognized = MockData.makeRecognizedData(
            categoryName: "Нет такой категории", paymentMethod: "bitcoin", date: nil
        )

        let viewModel = AddTransactionViewModel(
            account: account, prefilledType: .expense, editingTransaction: nil, recognizedData: recognized,
            onSaveNew: { _ in }, onSaveEdit: {}
        )

        #expect(viewModel.selectedCategory == nil)
        #expect(viewModel.paymentMethod == .other)
    }

    @Test("categories filters by universal + the currently selected type")
    func categoriesFilterByType() throws {
        let context = try TestModelContainer.makeContext()
        let populated = MockData.makePopulatedAccount(in: context)
        let viewModel = AddTransactionViewModel(
            account: populated.account, prefilledType: .expense, editingTransaction: nil,
            onSaveNew: { _ in }, onSaveEdit: {}
        )

        viewModel.type = .expense
        #expect(Set(viewModel.categories.map(\.name)) == ["Продукты", "Прочее"])

        viewModel.type = .income
        #expect(Set(viewModel.categories.map(\.name)) == ["Зарплата", "Прочее"])
    }

    @Test("canSave requires a non-blank title and a positive parseable amount")
    func canSaveValidation() {
        let account = MockData.makeAccount()
        let viewModel = AddTransactionViewModel(
            account: account, prefilledType: .expense, editingTransaction: nil,
            onSaveNew: { _ in }, onSaveEdit: {}
        )

        viewModel.title = "Кофе"
        for invalid in ["", "0", "-5", "abc"] {
            viewModel.amountText = invalid
            #expect(viewModel.canSave == false, "expected canSave == false for amountText \(invalid)")
        }

        viewModel.amountText = "12.34"
        #expect(viewModel.canSave == true)
        viewModel.amountText = "12,34"
        #expect(viewModel.canSave == true)

        viewModel.title = "   "
        viewModel.amountText = "12.34"
        #expect(viewModel.canSave == false)
    }

    @Test("canSave rounds a half-kopeck amount up to a non-zero minor unit")
    func canSaveRoundsHalfKopeckUp() {
        let account = MockData.makeAccount()
        let viewModel = AddTransactionViewModel(
            account: account, prefilledType: .expense, editingTransaction: nil,
            onSaveNew: { _ in }, onSaveEdit: {}
        )
        viewModel.title = "Мелочь"
        viewModel.amountText = "0.005"

        #expect(viewModel.canSave == true)
    }

    @Test("canSave rejects an amount that rounds down to zero minor units")
    func canSaveRejectsAmountRoundingToZero() {
        let account = MockData.makeAccount()
        let viewModel = AddTransactionViewModel(
            account: account, prefilledType: .expense, editingTransaction: nil,
            onSaveNew: { _ in }, onSaveEdit: {}
        )
        viewModel.title = "Мелочь"
        viewModel.amountText = "0.001"

        #expect(viewModel.canSave == false)
    }

    @Test("save() rejects an invalid amount without invoking callbacks")
    func saveRejectsInvalidAmount() {
        let account = MockData.makeAccount()
        var newCalled = false
        var editCalled = false
        let viewModel = AddTransactionViewModel(
            account: account, prefilledType: .expense, editingTransaction: nil,
            onSaveNew: { _ in newCalled = true }, onSaveEdit: { editCalled = true }
        )
        viewModel.title = "Кофе"
        viewModel.amountText = "abc"

        let result = viewModel.save()

        #expect(result == false)
        #expect(viewModel.showingValidationError == true)
        #expect(newCalled == false)
        #expect(editCalled == false)
    }

    @Test("save() converts comma decimals to minor units and trims the title")
    func saveConvertsAmount() throws {
        let account = MockData.makeAccount()
        let identity = MockUserIdentityService()
        identity.currentUserID = "creator-id"
        var savedTransaction: Transaction?
        let viewModel = AddTransactionViewModel(
            account: account, prefilledType: .expense, editingTransaction: nil, identity: identity,
            onSaveNew: { savedTransaction = $0 }, onSaveEdit: {}
        )
        viewModel.title = "  Кофе  "
        viewModel.amountText = "12,34"
        viewModel.note = ""

        let result = viewModel.save()

        #expect(result == true)
        let transaction = try #require(savedTransaction)
        #expect(transaction.title == "Кофе")
        #expect(transaction.amountMinorUnits == 1234)
        #expect(transaction.note == nil)
        #expect(transaction.createdByUserID == "creator-id")
    }

    @Test("save() rounds a half-kopeck amount to the nearest minor unit instead of truncating")
    func saveRoundsHalfKopeckAmount() {
        let account = MockData.makeAccount()
        var savedTransaction: Transaction?
        let viewModel = AddTransactionViewModel(
            account: account, prefilledType: .expense, editingTransaction: nil,
            onSaveNew: { savedTransaction = $0 }, onSaveEdit: {}
        )
        viewModel.title = "Мелочь"
        viewModel.amountText = "0.005"

        let result = viewModel.save()

        #expect(result == true)
        #expect(savedTransaction?.amountMinorUnits == 1)
    }

    @Test("save() rejects an amount that rounds down to zero minor units")
    func saveRejectsAmountRoundingToZero() {
        let account = MockData.makeAccount()
        var newCalled = false
        let viewModel = AddTransactionViewModel(
            account: account, prefilledType: .expense, editingTransaction: nil,
            onSaveNew: { _ in newCalled = true }, onSaveEdit: {}
        )
        viewModel.title = "Мелочь"
        viewModel.amountText = "0.001"

        let result = viewModel.save()

        #expect(result == false)
        #expect(viewModel.showingValidationError == true)
        #expect(newCalled == false)
    }

    @Test("save() on an existing transaction mutates it in place and stamps modifiedAt")
    func saveEditsExistingTransaction() {
        let account = MockData.makeAccount()
        let transaction = MockData.makeTransaction(title: "Старое", minorUnits: 10000, type: .expense)
        var editCalled = false
        let viewModel = AddTransactionViewModel(
            account: account, prefilledType: .expense, editingTransaction: transaction,
            onSaveNew: { _ in }, onSaveEdit: { editCalled = true }
        )
        viewModel.title = "Новое"
        viewModel.amountText = "200"

        let result = viewModel.save()

        #expect(result == true)
        #expect(editCalled == true)
        #expect(transaction.title == "Новое")
        #expect(transaction.amountMinorUnits == 20000)
        #expect(transaction.modifiedAt != nil)
    }
}
