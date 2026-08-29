import Testing
import SwiftData
@testable import iShareBudget

@MainActor
@Suite("CreateCategoryViewModel")
struct CreateCategoryViewModelTests {
    @Test("defaults for a new category")
    func newCategoryDefaults() {
        let account = MockData.makeAccount()
        let viewModel = CreateCategoryViewModel(account: account, kind: .expense, editingCategory: nil) { _ in }

        #expect(viewModel.name == "")
        #expect(viewModel.icon == "tag.fill")
        #expect(viewModel.colorHex == "007AFF")
        #expect(viewModel.isEditing == false)
    }

    @Test("prefills fields when editing an existing category")
    func editingPrefill() {
        let account = MockData.makeAccount()
        let category = MockData.makeCategory(name: "Спорт", kind: .expense, icon: "figure.run", colorHex: "16A085")
        let viewModel = CreateCategoryViewModel(account: account, kind: .expense, editingCategory: category) { _ in }

        #expect(viewModel.name == "Спорт")
        #expect(viewModel.icon == "figure.run")
        #expect(viewModel.colorHex == "16A085")
        #expect(viewModel.isEditing == true)
    }

    @Test("navigationTitleText and saveButtonText reflect editing state")
    func titlesReflectState() {
        let account = MockData.makeAccount()
        let creating = CreateCategoryViewModel(account: account, kind: .expense, editingCategory: nil) { _ in }
        let editing = CreateCategoryViewModel(account: account, kind: .expense, editingCategory: MockData.makeCategory()) { _ in }

        #expect(creating.navigationTitleText == "Новая категория")
        #expect(creating.saveButtonText == "Создать")
        #expect(editing.navigationTitleText == "Редактировать категорию")
        #expect(editing.saveButtonText == "Сохранить")
    }

    @Test("canSave requires a non-blank name")
    func canSaveValidation() {
        let account = MockData.makeAccount()
        let viewModel = CreateCategoryViewModel(account: account, kind: .expense, editingCategory: nil) { _ in }

        viewModel.name = ""
        #expect(viewModel.canSave == false)

        viewModel.name = "   "
        #expect(viewModel.canSave == false)

        viewModel.name = "Такси"
        #expect(viewModel.canSave == true)
    }

    @Test("save without attach(context:) does nothing")
    func saveWithoutContext() {
        let account = MockData.makeAccount()
        var savedCategory: Category?
        let viewModel = CreateCategoryViewModel(account: account, kind: .expense, editingCategory: nil) { savedCategory = $0 }
        viewModel.name = "Такси"

        viewModel.save()

        #expect(savedCategory == nil)
    }

    @Test("save creates a new category attached to the account")
    func saveCreatesCategory() throws {
        let context = try TestModelContainer.makeContext()
        let account = MockData.makeAccount()
        context.insert(account)

        var savedCategory: Category?
        let viewModel = CreateCategoryViewModel(account: account, kind: .expense, editingCategory: nil) { savedCategory = $0 }
        viewModel.attach(context: context)
        viewModel.name = "  Такси  "
        viewModel.icon = "car.fill"
        viewModel.colorHex = "3498DB"

        viewModel.save()

        let saved = try #require(savedCategory)
        #expect(saved.name == "Такси")
        #expect(saved.icon == "car.fill")
        #expect(saved.colorHex == "3498DB")
        #expect(saved.kind == .expense)
        #expect(saved.account?.id == account.id)
    }

    @Test("save mutates the existing category when editing")
    func saveEditsCategory() throws {
        let context = try TestModelContainer.makeContext()
        let account = MockData.makeAccount()
        let category = MockData.makeCategory(name: "Старое имя", kind: .expense)
        category.account = account
        context.insert(account)
        context.insert(category)

        var savedCategory: Category?
        let viewModel = CreateCategoryViewModel(account: account, kind: .expense, editingCategory: category) { savedCategory = $0 }
        viewModel.attach(context: context)
        viewModel.name = "Новое имя"

        viewModel.save()

        #expect(savedCategory?.id == category.id)
        #expect(category.name == "Новое имя")
    }
}
