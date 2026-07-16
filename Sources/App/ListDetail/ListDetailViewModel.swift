//
//  ListDetailViewModel.swift
//  CloudKitSharing
//
//  Created by Danil on 16.07.2026.
//

import SwiftUI
import CloudKit
import Combine
import SwiftData

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

    // Add transaction state
    @Published var showingAddTransaction = false
    @Published var prefilledType: TransactionType = .expense

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

    func presentAddTransaction(type: TransactionType) {
        prefilledType = type
        showingAddTransaction = true
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

    func addItem(_ item: Transaction) {
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
