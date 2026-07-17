//
//  ListDetailViewModel.swift
//  CloudKitSharing
//
//  Created by Danil on 16.07.2026.
//

import SwiftData
import SwiftUI
import CloudKit
import Combine

@MainActor
final class ListDetailViewModel: ObservableObject {
    let list: Account

    // Sharing state
    @Published var showingShareSheet = false
    @Published var activeShare: CKShare?
    @Published var activeContainer: CKContainer?
    @Published var showingError = false
    @Published var errorMessage = ""
    @Published var showingLeaveConfirmation = false
    @Published var isSyncing = false

    // Add / edit transaction
    @Published var showingAddTransaction = false
    @Published var prefilledType: TransactionType = .expense
    @Published var editingTransaction: Transaction?

    // Month + filters
    @Published var selectedMonth: Date = Calendar.current.startOfMonth(for: .now)
    @Published var selectedCategory: Category?
    @Published var selectedType: TransactionType?

    // Category creation
    @Published var showingCreateCategory = false
    @Published var categoryCreationKind: TransactionType = .expense

    private var modelContext: ModelContext?

    init(list: Account) {
        self.list = list
    }

    func attach(context: ModelContext) {
        self.modelContext = context
    }

    var bannerText: String {
        UserIdentityService.shared.isCurrentUserOwner(of: list)
            ? "Вы делитесь этим списком"
            : "Доступно вам по приглашению"
    }

    // MARK: - Фильтрация по месяцу + фильтрам

    func filteredItems(from allItems: [Transaction]) -> [Transaction] {
        let calendar = Calendar.current
        return allItems.filter { item in
            guard calendar.isDate(item.date, equalTo: selectedMonth, toGranularity: .month) else {
                return false
            }
            if let selectedCategory, item.category?.id != selectedCategory.id {
                return false
            }
            if let selectedType, item.type != selectedType {
                return false
            }
            return true
        }
    }

    func summary(for items: [Transaction]) -> (income: Decimal, expense: Decimal) {
        let income = items.filter { $0.type == .income }.reduce(Decimal(0)) { $0 + $1.amount }
        let expense = items.filter { $0.type == .expense }.reduce(Decimal(0)) { $0 + $1.amount }
        return (income, expense)
    }

    func breakdownSlices(for items: [Transaction]) -> [CategoryBreakdownSlice] {
        let expenses = items.filter { $0.type == .expense }
        let total = expenses.reduce(Decimal(0)) { $0 + $1.amount }
        guard total > 0 else { return [] }

        let totalDouble = (total as NSDecimalNumber).doubleValue
        let grouped = Dictionary(grouping: expenses) { $0.category?.id }

        return grouped.compactMap { _, transactions -> CategoryBreakdownSlice? in
            guard let category = transactions.first?.category else { return nil }
            let sum = transactions.reduce(Decimal(0)) { $0 + $1.amount }
            let sumDouble = (sum as NSDecimalNumber).doubleValue
            return CategoryBreakdownSlice(
                categoryName: category.name,
                emoji: category.icon,
                amount: sumDouble,
                percentage: sumDouble / totalDouble * 100,
                colorHex: category.colorHex
            )
        }
        .sorted { $0.amount > $1.amount }
    }

    // MARK: - Actions

    func presentAddTransaction(type: TransactionType) {
        editingTransaction = nil
        prefilledType = type
        showingAddTransaction = true
    }

    func presentEditTransaction(_ item: Transaction) {
        editingTransaction = item
        prefilledType = item.type
        showingAddTransaction = true
    }

    func presentCreateCategory(kind: TransactionType) {
        categoryCreationKind = kind
        showingCreateCategory = true
    }

    func presentSharing() {
        guard SharingManager.shared.isSharingAvailable else {
            errorMessage = "iCloud недоступен. Войдите в iCloud в настройках."
            showingError = true
            return
        }

        Task {
            guard let context = modelContext else { return }
            do {
                let (share, container) = try await SharingManager.shared.fetchOrCreateShare(
                    for: list, context: context
                )
                activeShare = share
                activeContainer = container
                showingShareSheet = true
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    func saveNewItem(_ item: Transaction) {
        guard let context = modelContext else { return }
        item.account = list
        context.insert(item)
        try? context.save()

        if list.isShared {
            Task {
                try? await SharingManager.shared.pushItem(item, for: list)
            }
        }
    }

    func saveEditedItem() {
        guard let context = modelContext else { return }
        try? context.save()

        if list.isShared, let item = editingTransaction {
            Task {
                try? await SharingManager.shared.pushItem(item, for: list)
            }
        }
    }

    func deleteItem(_ item: Transaction) {
        guard let context = modelContext else { return }
        context.delete(item)
        try? context.save()

        if list.isShared {
            Task {
                try? await SharingManager.shared.removeItem(item, for: list)
            }
        }
    }

    func leaveList() {
        guard let context = modelContext else { return }
        Task {
            try? await SharingManager.shared.leaveSharedList(list, context: context)
        }
    }

    func syncSharedItems() async {
        guard list.isShared, !isSyncing, let context = modelContext else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await SharingManager.shared.syncItems(for: list, context: context)
        } catch {
            errorMessage = "Не удалось синхронизировать: \(error.localizedDescription)"
            showingError = true
        }
    }
}

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components) ?? date
    }
}
