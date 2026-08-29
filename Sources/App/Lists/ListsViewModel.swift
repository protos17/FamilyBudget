//
//  ListsViewModel.swift
//  CloudKitSharing
//
//  Created by Danil on 17.07.2026.
//

import SwiftUI
import SwiftData

@MainActor
final class ListsViewModel: ObservableObject {
    @Published var showingAddList = false
    @Published var sharingEndedName: String?
    @Published var accountPendingDeletion: Account?
    @Published var showingDeletionError = false
    @Published var deletionErrorMessage = ""
    @Published var accountPendingLeave: Account?
    @Published var accountPendingDuplication: Account?

    private var modelContext: ModelContext?
    private let sharing: any SharingProviding

    init(sharing: any SharingProviding = SharingManager.shared) {
        self.sharing = sharing
    }

    func attach(context: ModelContext) {
        self.modelContext = context
    }

    func addList(sortOrder: Int, newAccount: Account) {
        guard let modelContext else { return }
        newAccount.sortOrder = sortOrder
        try? modelContext.save()
    }

    func deleteAccount(_ account: Account) {
        guard let modelContext else { return }
        if account.isShared {
            Task {
                do {
                    try await sharing.stopSharing(account, context: modelContext)
                    modelContext.delete(account)
                    try? modelContext.save()
                } catch {
                    deletionErrorMessage = "Не удалось удалить бюджет: \(error.localizedDescription)"
                    showingDeletionError = true
                }
            }
        } else {
            modelContext.delete(account)
            try? modelContext.save()
        }
    }

    func leaveAccount(_ account: Account) {
        guard let modelContext else { return }
        Task {
            try? await sharing.leaveSharedList(account, context: modelContext)
        }
    }

    func handleSharingEndedNotification(_ notification: Notification) {
        if let name = notification.userInfo?["listName"] as? String {
            sharingEndedName = name
        }
    }

    func checkForEndedSharing(in lists: [Account]) async {
        guard let modelContext else { return }
        let sharedLists = lists.filter(\.isShared)
        guard !sharedLists.isEmpty else { return }
        await sharing.checkForEndedSharing(in: sharedLists, context: modelContext)
    }

    func refreshSharedZones() async {
        guard let modelContext else { return }
        await sharing.discoverSharedZones(context: modelContext)
    }
}
