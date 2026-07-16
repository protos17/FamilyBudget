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
    let onSave: (Transaction) -> Void

    @Published var type: TransactionType
    @Published var title: String = ""
    @Published var amountText: String = ""
    @Published var date: Date = .now
    @Published var selectedCategory: Category?
    @Published var note: String = ""
    @Published var paymentMethod: PaymentMethod = .card
    @Published var showingValidationError = false

    init(account: Account, prefilledType: TransactionType, onSave: @escaping (Transaction) -> Void) {
        self.account = account
        self.type = prefilledType
        self.onSave = onSave
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

        onSave(item)
        return true
    }
}

extension CategoryKind {
    func matches(_ type: TransactionType) -> Bool {
        switch (self, type) {
        case (.income, .income), (.expense, .expense):
            return true
        default:
            return false
        }
    }
}
