//
//  AccountFormViewModel.swift
//  FamilyBudget
//
//  Created by Danil on 17.07.2026.
//

import SwiftUI
import SwiftData
import Combine

@MainActor
final class AccountFormViewModel: ObservableObject {
    let editingAccount: Account?
    let duplicateFrom: Account?
    let onSave: (Account) -> Void
    
    @Published var name: String
    @Published var icon: String
    @Published var colorHex: String
    @Published var currencyCode: String
    @Published var showingSymbolPicker = false
    
    private var modelContext: ModelContext?
    private let identity: any UserIdentityProviding

    var isEditing: Bool { editingAccount != nil }
    
    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    var navigationTitleText: LocalizedStringKey {
        if editingAccount != nil {
            "Редактировать бюджет"
        } else if duplicateFrom != nil {
            "Копия бюджета"
        } else {
            "Новый бюджет"
        }
    }
    
    init(
        editingAccount: Account?,
        duplicateFrom: Account?,
        identity: any UserIdentityProviding = UserIdentityService.shared,
        onSave: @escaping (Account) -> Void
    ) {
        self.editingAccount = editingAccount
        self.duplicateFrom = duplicateFrom
        self.identity = identity
        self.onSave = onSave
        self.name = editingAccount?.name ?? ""
        self.icon = editingAccount?.icon ?? duplicateFrom?.icon ?? "creditcard.fill"
        self.colorHex = editingAccount?.colorHex ?? duplicateFrom?.colorHex ?? ColorPalette.all[0]
        self.currencyCode = editingAccount?.currencyCode ?? duplicateFrom?.currencyCode ?? "RUB"
    }
    
    func attach(context: ModelContext) {
        self.modelContext = context
    }
    
    func save() {
        guard let modelContext else { return }
        
        if let existing = editingAccount {
            existing.name = name.trimmingCharacters(in: .whitespaces)
            existing.icon = icon
            existing.colorHex = colorHex
            existing.currencyCode = currencyCode
            try? modelContext.save()
            onSave(existing)
        } else {
            let account = Account(name: name.trimmingCharacters(in: .whitespaces), currencyCode: currencyCode)
            account.icon = icon
            account.colorHex = colorHex
            modelContext.insert(account)
            
            if let source = duplicateFrom {
                duplicateContents(from: source, into: account, context: modelContext)
            } else {
                DefaultCategories.seed(into: account, context: modelContext)
            }
            
            try? modelContext.save()
            onSave(account)
        }
    }
    
    private func duplicateContents(from source: Account, into newAccount: Account, context: ModelContext) {
        var categoryMap: [UUID: Category] = [:]
        
        for oldCategory in source.categories ?? [] {
            let newCategory = Category(
                name: oldCategory.name,
                icon: oldCategory.icon,
                colorHex: oldCategory.colorHex,
                kind: oldCategory.kind,
                sortOrder: oldCategory.sortOrder
            )
            newCategory.account = newAccount
            context.insert(newCategory)
            categoryMap[oldCategory.id] = newCategory
        }
        
        for oldTransaction in source.transactions ?? [] {
            let newTransaction = Transaction(
                title: oldTransaction.title,
                amountMinorUnits: oldTransaction.amountMinorUnits,
                type: oldTransaction.type,
                date: oldTransaction.date,
                createdByUserID: identity.currentUserID
            )
            newTransaction.note = oldTransaction.note
            newTransaction.paymentMethod = oldTransaction.paymentMethod
            newTransaction.tags = oldTransaction.tags
            newTransaction.category = oldTransaction.category.flatMap { categoryMap[$0.id] }
            newTransaction.account = newAccount
            context.insert(newTransaction)
        }
    }
}
