//
//  CloudKitShareHandler.swift
//  iShareBudget
//
//  Created by Danil on 29.08.2026.
//

import SwiftUI
import SwiftData

struct CloudKitShareHandlerView: View {
    @ObservedObject private var coordinator = CloudKitShareCoordinator.shared
    @Environment(\.modelContext) private var modelContext
    @State private var isAccepting = false
    @State private var showingAccepted = false
    @State private var acceptedListName = ""
    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .overlay {
                if isAccepting {
                    ProgressView("Подключение к бюджету...")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .onChange(of: coordinator.pendingShareMetadata) { _, metadata in
                guard let metadata else { return }
                Task {
                    isAccepting = true
                    defer {
                        CloudKitShareCoordinator.shared.clearPendingShare()
                        isAccepting = false
                    }
                    do {
                        let list = try await SharingManager.shared.acceptShare(metadata, context: modelContext)
                        acceptedListName = list.name
                        showingAccepted = true
                    } catch {
                        errorMessage = "Не удалось подключиться к бюджету: \(error.localizedDescription)"
                        showingError = true
                    }
                }
            }
            .alert("Бюджет добавлен", isPresented: $showingAccepted) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Теперь у вас есть доступ к \"\(acceptedListName)\".")
            }
            .alert("Ошибка", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
    }
}
