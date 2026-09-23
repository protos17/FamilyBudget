import Foundation
import SwiftData
@testable import iShareBudget

// `Category` clashes with the Objective-C runtime's global `Category` typedef
// (<objc/runtime.h>) once the type is reached via `@testable import` instead of
// as a local module declaration. This alias, declared once in the test module,
// resolves the ambiguity for every unqualified `Category` reference in this target.
typealias Category = iShareBudget.Category

@MainActor
enum MockData {
    static func makeAccount(
        name: String = "Тестовый бюджет",
        currencyCode: String = "RUB",
        isShared: Bool = false,
        ownerID: String? = nil,
        icon: String = "creditcard",
        colorHex: String = "007AFF"
    ) -> Account {
        let account = Account(name: name, icon: icon, colorHex: colorHex, currencyCode: currencyCode)
        account.isShared = isShared
        account.ownerID = ownerID
        return account
    }

    static func makeSharedAccount(
        name: String = "Общий бюджет",
        ownerID: String? = "owner-id"
    ) -> Account {
        let account = makeAccount(name: name, isShared: true, ownerID: ownerID)
        account.shareRecordID = "share-record-id"
        account.shareZoneOwnerName = "zone-owner"
        return account
    }

    static func makeCategory(
        name: String = "Продукты",
        kind: CategoryKind = .expense,
        icon: String = "cart.fill",
        colorHex: String = "2ECC71",
        createdAt: Date = .now
    ) -> Category {
        let category = Category(name: name, icon: icon, colorHex: colorHex, kind: kind)
        category.createdAt = createdAt
        return category
    }

    static func makeTransaction(
        title: String = "Покупка",
        minorUnits: Int = 10000,
        type: TransactionType = .expense,
        date: Date = .now,
        category: Category? = nil,
        paymentMethod: PaymentMethod = .card,
        note: String? = nil,
        createdByUserID: String? = nil
    ) -> Transaction {
        let transaction = Transaction(
            title: title,
            amountMinorUnits: minorUnits,
            type: type,
            date: date,
            note: note,
            paymentMethod: paymentMethod,
            createdByUserID: createdByUserID
        )
        transaction.category = category
        return transaction
    }

    static func makeRecognizedData(
        title: String = "Кофе",
        amount: Double = 350.5,
        categoryName: String? = nil,
        paymentMethod: String? = "card",
        date: String? = nil,
        note: String? = nil
    ) -> RecognizedTransactionData {
        RecognizedTransactionData(
            title: title,
            amount: amount,
            categoryName: categoryName,
            paymentMethod: paymentMethod,
            date: date,
            note: note
        )
    }

    struct PopulatedAccount {
        let account: Account
        let expenseCategory: Category
        let incomeCategory: Category
        let universalCategory: Category
        let transactions: [Transaction]
    }

    /// Бюджет с категориями трёх типов и транзакциями за текущий и прошлый месяц —
    /// база для тестов фильтрации, агрегации и разбивки по категориям.
    static func makePopulatedAccount(in context: ModelContext) -> PopulatedAccount {
        let account = makeAccount()
        let expenseCategory = makeCategory(
            name: "Продукты", kind: .expense, icon: "cart.fill", colorHex: "2ECC71",
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let incomeCategory = makeCategory(
            name: "Зарплата", kind: .income, icon: "banknote.fill", colorHex: "34C759",
            createdAt: Date(timeIntervalSince1970: 2)
        )
        let universalCategory = makeCategory(
            name: "Прочее", kind: .universal, icon: "ellipsis.circle.fill", colorHex: "95A5A6",
            createdAt: Date(timeIntervalSince1970: 3)
        )
        account.categories = [expenseCategory, incomeCategory, universalCategory]

        let now = Date.now
        let lastMonth = Calendar.current.date(byAdding: .month, value: -1, to: now) ?? now

        let transactions = [
            makeTransaction(title: "Обед", minorUnits: 50000, type: .expense, date: now, category: expenseCategory),
            makeTransaction(title: "Такси", minorUnits: 30000, type: .expense, date: now, category: expenseCategory),
            makeTransaction(title: "Зарплата", minorUnits: 10000000, type: .income, date: now, category: incomeCategory),
            makeTransaction(title: "Прошлый месяц", minorUnits: 20000, type: .expense, date: lastMonth, category: expenseCategory)
        ]

        for transaction in transactions {
            transaction.account = account
            context.insert(transaction)
        }
        context.insert(expenseCategory)
        context.insert(incomeCategory)
        context.insert(universalCategory)
        context.insert(account)
        try? context.save()

        return PopulatedAccount(
            account: account,
            expenseCategory: expenseCategory,
            incomeCategory: incomeCategory,
            universalCategory: universalCategory,
            transactions: transactions
        )
    }
}
