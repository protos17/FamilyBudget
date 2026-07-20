//
//  ShareInviteView.swift
//  ShareBudget
//
//  Created by Danil on 17.07.2026.
//

import SwiftUI

struct ShareInviteView: View {
    let account: Account
    @ObservedObject var viewModel: ListDetailViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    private var permissions: PermissionManager { .shared }
    
    var body: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: "person.2.fill")
                        .foregroundStyle(.blue)
                    Text(viewModel.bannerText)
                }
            }
            
            if !account.isShared {
                if (account.transactions ?? []).isEmpty {
                    Section {
                        Label(
                            "Добавьте хотя бы одну операцию перед тем, как поделиться бюджетом",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.orange)
                        .font(.subheadline)
                    }
                } else if permissions.canShareList(account) {
                    Section {
                        Button {
                            viewModel.presentSharing()
                        } label: {
                            Label("Пригласить участника", systemImage: "person.badge.plus")
                        }
                    }
                }
            }
            
            if account.isShared && permissions.canManageSharing(for: account) {
                Section {
                    Button {
                        viewModel.presentSharing()
                    } label: {
                        Label("Управление участниками", systemImage: "person.2.fill")
                    }
                }
            }
            
            if permissions.canLeaveList(account) {
                Section {
                    Button(role: .destructive) {
                        viewModel.showingLeaveConfirmation = true
                    } label: {
                        Label("Покинуть бюджет", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
        }
        .navigationTitle("Общий доступ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Готово") { dismiss() }
            }
        }
        .confirmationDialog(
            "Покинуть \"\(account.name)\"?",
            isPresented: $viewModel.showingLeaveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Покинуть", role: .destructive) {
                viewModel.leaveList()
            }
        } message: {
            Text("Вы потеряете доступ к этому бюджету.")
        }
    }
}
