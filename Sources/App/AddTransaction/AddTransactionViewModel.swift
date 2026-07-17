//
//  AddTransactionViewModel.swift
//  CloudKitSharing
//
//  Created by Danil on 17.07.2026.
//

import SwiftUI
import Combine

@MainActor
final class AddTransactionViewModel: ObservableObject {
    let account: Account
    let editingTransaction: Transaction?
    let onSaveNew: (Transaction) -> Void
    let onSaveEdit: () -> Void

    @Published var type: TransactionType
    @Published var title: String
    @Published var amountText: String
    @Published var date: Date
    @Published var selectedCategory: Category?
    @Published var note: String
    @Published var paymentMethod: PaymentMethod
    @Published var showingValidationError = false
    @Published var showingCreateCategory = false

    var isEditing: Bool { editingTransaction != nil }

    init(
        account: Account,
        prefilledType: TransactionType,
        editingTransaction: Transaction?,
        onSaveNew: @escaping (Transaction) -> Void,
        onSaveEdit: @escaping () -> Void
    ) {
        self.account = account
        self.editingTransaction = editingTransaction
        self.onSaveNew = onSaveNew
        self.onSaveEdit = onSaveEdit

        if let existing = editingTransaction {
            self.type = existing.type
            self.title = existing.title
            self.amountText = "\(existing.amount)"
            self.date = existing.date
            self.selectedCategory = existing.category
            self.note = existing.note ?? ""
            self.paymentMethod = existing.paymentMethod
        } else {
            self.type = prefilledType
            self.title = ""
            self.amountText = ""
            self.date = .now
            self.selectedCategory = nil
            self.note = ""
            self.paymentMethod = .card
        }
    }

    var categories: [Category] {
        (account.categories ?? []).filter {
            $0.kind == .universal || $0.kind.matches(type)
        }
    }

    var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && parsedAmount != nil
    }

    private var parsedAmount: Int? {
        let normalized = amountText.replacingOccurrences(of: ",", with: ".")
        guard let decimal = Decimal(string: normalized), decimal > 0 else { return nil }
        return Int(truncating: (decimal * 100) as NSDecimalNumber)
    }

    func save() -> Bool {
        guard let amountMinorUnits = parsedAmount else {
            showingValidationError = true
            return false
        }

        if let existing = editingTransaction {
            existing.title = title.trimmingCharacters(in: .whitespaces)
            existing.amountMinorUnits = amountMinorUnits
            existing.type = type
            existing.date = date
            existing.category = selectedCategory
            existing.paymentMethod = paymentMethod
            existing.note = note.isEmpty ? nil : note
            existing.modifiedAt = .now
            onSaveEdit()
        } else {
            let item = Transaction(
                title: title.trimmingCharacters(in: .whitespaces),
                amountMinorUnits: amountMinorUnits,
                type: type,
                date: date,
                createdByUserID: UserIdentityService.shared.currentUserID
            )
            item.category = selectedCategory
            item.paymentMethod = paymentMethod
            item.note = note.isEmpty ? nil : note
            onSaveNew(item)
        }
        return true
    }
}
