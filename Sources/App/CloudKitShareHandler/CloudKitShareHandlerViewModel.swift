//
//  CloudKitShareHandlerViewModel.swift
//  iShareBudget
//
//  Created by Danil on 29.08.2026.
//

import SwiftUI
import CloudKit
import SwiftData

@MainActor
final class CloudKitShareHandlerViewModel: ObservableObject {
    @Published var isAccepting = false
    @Published var showingAccepted = false
    @Published var acceptedListName = ""
    @Published var showingError = false
    @Published var errorMessage = ""

    private let sharing: any SharingProviding
    private let pendingShare: any PendingShareClearing

    init(
        sharing: any SharingProviding = SharingManager.shared,
        pendingShare: any PendingShareClearing = CloudKitShareCoordinator.shared
    ) {
        self.sharing = sharing
        self.pendingShare = pendingShare
    }

    func acceptShare(_ metadata: CKShare.Metadata?, context: ModelContext) async {
        guard let metadata else { return }
        await performAccept { [sharing] in
            try await sharing.acceptShare(metadata, context: context)
        }
    }

    /// Extracted seam so tests can exercise the success/failure branches without a real `CKShare.Metadata`.
    func performAccept(_ accept: () async throws -> Account) async {
        isAccepting = true
        defer {
            pendingShare.clearPendingShare()
            isAccepting = false
        }
        do {
            let list = try await accept()
            acceptedListName = list.name
            showingAccepted = true
        } catch {
            errorMessage = "Не удалось подключиться к бюджету: \(error.localizedDescription)"
            showingError = true
        }
    }
}
