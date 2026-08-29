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

    func acceptShare(_ metadata: CKShare.Metadata?, context: ModelContext) async {
        guard let metadata else { return }
        isAccepting = true
        defer {
            CloudKitShareCoordinator.shared.clearPendingShare()
            isAccepting = false
        }
        do {
            let list = try await SharingManager.shared.acceptShare(metadata, context: context)
            acceptedListName = list.name
            showingAccepted = true
        } catch {
            errorMessage = "Не удалось подключиться к бюджету: \(error.localizedDescription)"
            showingError = true
        }
    }
}
