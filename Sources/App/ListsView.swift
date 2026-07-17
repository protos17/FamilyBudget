//
//  ListsView.swift
//  CloudKitSharing
//
//  Shows all lists. Shared lists display a badge with participant count.
//

import SwiftUI
import SwiftData

struct ListsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Account.sortOrder) private var lists: [Account]
    @State private var showingAddList = false
    @State private var sharingEndedName: String?
    @State private var accountPendingDeletion: Account?
    @State private var showingDeletionError = false
    @State private var deletionErrorMessage = ""
    @State private var accountPendingLeave: Account?
    private let sharingHealthTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                if !UserIdentityService.shared.isCloudKitAvailable {
                    iCloudBanner
                        .padding(.horizontal)
                        .padding(.top, 8)
                }
                
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(lists) { list in
                        NavigationLink(destination: ListDetailView(list: list)) {
                            BudgetCard(list: list)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if PermissionManager.shared.canDeleteList(list) {
                                Button(role: .destructive) {
                                    accountPendingDeletion = list
                                } label: {
                                    Label("Удалить бюджет", systemImage: "trash")
                                }
                            } else if PermissionManager.shared.canLeaveList(list) {
                                Button(role: .destructive) {
                                    accountPendingLeave = list
                                } label: {
                                    Label("Покинуть бюджет", systemImage: "rectangle.portrait.and.arrow.right")
                                }
                            }
                        }
                    }
                    addBudgetCard
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Бюджеты")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddList = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddList) {
                AccountFormView(onSave: { newAccount in
                    newAccount.sortOrder = lists.count
                    try? modelContext.save()
                })
            }
            .overlay {
                if lists.isEmpty {
                    ContentUnavailableView(
                        "Нет бюджетов",
                        systemImage: "creditcard",
                        description: Text("Нажмите +, чтобы создать первый бюджет")
                    )
                }
            }
            .confirmationDialog(
                "Удалить \"\(accountPendingDeletion?.name ?? "")\"?",
                isPresented: Binding(
                    get: { accountPendingDeletion != nil },
                    set: { if !$0 { accountPendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Удалить", role: .destructive) {
                    if let account = accountPendingDeletion {
                        deleteAccount(account)
                    }
                    accountPendingDeletion = nil
                }
                Button("Отмена", role: .cancel) {
                    accountPendingDeletion = nil
                }
            } message: {
                if let account = accountPendingDeletion, account.isShared {
                    Text("Этот бюджет расшарен. Удаление прекратит доступ для всех участников. Все операции и категории будут удалены безвозвратно.")
                } else {
                    Text("Все операции и категории этого бюджета будут удалены безвозвратно.")
                }
            }
            .confirmationDialog(
                "Покинуть \"\(accountPendingLeave?.name ?? "")\"?",
                isPresented: Binding(
                    get: { accountPendingLeave != nil },
                    set: { if !$0 { accountPendingLeave = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Покинуть", role: .destructive) {
                    if let account = accountPendingLeave {
                        leaveAccount(account)
                    }
                    accountPendingLeave = nil
                }
                Button("Отмена", role: .cancel) {
                    accountPendingLeave = nil
                }
            } message: {
                Text("Вы потеряете доступ к этому бюджету. Добавленные вами операции останутся у других участников.")
            }
            .onReceive(NotificationCenter.default.publisher(for: SharingManager.sharingEndedNotification)) { notification in
                if let name = notification.userInfo?["listName"] as? String {
                    sharingEndedName = name
                }
            }
            .task {
                await checkForEndedSharing()
            }
            .onReceive(sharingHealthTimer) { _ in
                Task { await checkForEndedSharing() }
            }
            .alert("Доступ прекращён", isPresented: .init(
                get: { sharingEndedName != nil },
                set: { if !$0 { sharingEndedName = nil } }
            )) {
                Button("OK", role: .cancel) { sharingEndedName = nil }
            } message: {
                if let name = sharingEndedName {
                    Text("\"\(name)\" больше не доступен как общий. Локальная копия сохранена.")
                }
            }
            .alert("Ошибка", isPresented: $showingDeletionError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deletionErrorMessage)
            }
        }
    }
    
    private var addBudgetCard: some View {
        Button {
            showingAddList = true
        } label: {
            VStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text("Новый бюджет")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 150)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color(.tertiaryLabel), style: StrokeStyle(lineWidth: 1.5, dash: [6]))
            )
        }
        .buttonStyle(.plain)
    }
    
    private var iCloudBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "icloud.slash")
                .font(.title3)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("iCloud недоступен")
                    .font(.subheadline.weight(.medium))
                Text("Войдите в iCloud в настройках, чтобы включить общий доступ.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color(.systemOrange).opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
    
    private func deleteAccount(_ account: Account) {
        if account.isShared {
            Task {
                do {
                    try await SharingManager.shared.stopSharing(account, context: modelContext)
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
    
    private func leaveAccount(_ account: Account) {
        Task {
            try? await SharingManager.shared.leaveSharedList(account, context: modelContext)
        }
    }
    
    private func checkForEndedSharing() async {
        let sharedLists = lists.filter(\.isShared)
        guard !sharedLists.isEmpty else { return }
        await SharingManager.shared.checkForEndedSharing(in: sharedLists, context: modelContext)
    }
}

// MARK: - Budget Card

private struct BudgetCard: View {
    let list: Account
    
    private var currentMonthTransactions: [Transaction] {
        (list.transactions ?? []).filter {
            Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .month)
        }
    }
    
    private var balance: Decimal {
        let income = currentMonthTransactions.filter { $0.type == .income }.reduce(Decimal(0)) { $0 + $1.amount }
        let expense = currentMonthTransactions.filter { $0.type == .expense }.reduce(Decimal(0)) { $0 + $1.amount }
        return income - expense
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: list.icon)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color(hex: list.colorHex))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                
                Spacer()
                
                if list.isShared {
                    Image(systemName: "person.2.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(list.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                Text("\(balance.formattedAsCurrency(code: list.currencyCode)) в этом месяце")
                    .font(.caption)
                    .foregroundStyle(balance >= 0 ? Color.secondary : Color.red)
                    .lineLimit(1)
            }
            
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(height: 150)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        )
    }
}
