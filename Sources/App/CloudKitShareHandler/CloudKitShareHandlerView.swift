//
//  CloudKitShareHandler.swift
//  iShareBudget
//
//  Created by Danil on 29.08.2026.
//

import SwiftUI
import SwiftData

struct CloudKitShareHandlerView: View {
    @StateObject private var viewModel = CloudKitShareHandlerViewModel()
    @ObservedObject private var coordinator = CloudKitShareCoordinator.shared
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .overlay {
                if viewModel.isAccepting {
                    ProgressView("Подключение к бюджету...")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .onChange(of: coordinator.pendingShareMetadata) { _, metadata in
                Task {
                    await viewModel.acceptShare(metadata, context: modelContext)
                }
            }
            .alert("Бюджет добавлен", isPresented: $viewModel.showingAccepted) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Теперь у вас есть доступ к \"\(viewModel.acceptedListName)\".")
            }
            .alert("Ошибка", isPresented: $viewModel.showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage)
            }
    }
}
