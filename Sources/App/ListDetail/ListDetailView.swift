//
//  ListDetailView.swift
//  CloudKitSharing
//
//  Shows items in a list with permission-aware actions.
//  The toolbar includes a Share button that launches UICloudSharingController.
//

import SwiftUI
import SwiftData
import CloudKit

struct ListDetailView: View {
    let list: Account
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [Transaction]

    @StateObject private var viewModel: ListDetailViewModel

    private var permissions: PermissionManager { .shared }

    init(list: Account) {
        self.list = list
        let listID = list.id
        _items = Query(
            filter: #Predicate<Transaction> { $0.account?.id == listID },
            sort: \.date,
            order: .reverse
        )
        _viewModel = StateObject(wrappedValue: ListDetailViewModel(list: list))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 10) {
                    if list.isShared {
                        sharingBanner
                    }

                    ForEach(items) { item in
                        ItemCard(
                            item: item,
                            list: list,
                            onDelete: { viewModel.deleteItem(item) }
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .overlay {
                if items.isEmpty {
                    ContentUnavailableView(
                        "Нет операций",
                        systemImage: "creditcard",
                        description: Text("Добавьте доход или расход ниже.")
                    )
                }
            }

            if permissions.canAddItem(to: list) {
                quickActionButtons
            }
        }
        .navigationTitle(list.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                shareButton
            }
        }
        .sheet(isPresented: $viewModel.showingShareSheet) {
            if let share = viewModel.activeShare, let container = viewModel.activeContainer {
                CloudSharingView(
                    list: list,
                    context: modelContext,
                    container: container,
                    share: share
                )
                .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $viewModel.showingAddTransaction) {
            AddTransactionView(
                account: list,
                prefilledType: viewModel.prefilledType,
                onSave: { newItem in
                    viewModel.addItem(newItem)
                }
            )
        }
        .alert("Ошибка", isPresented: $viewModel.showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
        .onAppear {
            viewModel.attach(context: modelContext)
        }
        .task {
            await viewModel.syncSharedItems()
        }
        .refreshable {
            await viewModel.syncSharedItems()
        }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            guard list.isShared else { return }
            Task { await viewModel.syncSharedItems() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .modelContextDidSave)) { _ in
            guard list.isShared else { return }
            Task { await viewModel.syncSharedItems() }
        }
        .onReceive(NotificationCenter.default.publisher(for: SharingManager.itemsDidSyncNotification)) { _ in
            Task { await viewModel.syncSharedItems() }
        }
        .confirmationDialog(
            "Покинуть \"\(list.name)\"?",
            isPresented: $viewModel.showingLeaveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Покинуть", role: .destructive) {
                viewModel.leaveList()
            }
        } message: {
            Text("Вы потеряете доступ к этому списку. Добавленные вами операции останутся у других участников.")
        }
    }

    // MARK: - Sharing Banner

    private var sharingBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.2.fill")
                .foregroundStyle(.blue)
            Text(viewModel.bannerText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            if viewModel.isSyncing {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(Color(.systemBlue).opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Share Button

    private var shareButton: some View {
        Menu {
            if !list.isShared && permissions.canShareList(list) {
                Button {
                    viewModel.presentSharing()
                } label: {
                    Label("Поделиться списком", systemImage: "person.badge.plus")
                }
            }

            if list.isShared && permissions.canManageSharing(for: list) {
                Button {
                    viewModel.presentSharing()
                } label: {
                    Label("Управление доступом", systemImage: "person.2.fill")
                }
            }

            if permissions.canLeaveList(list) {
                Button(role: .destructive) {
                    viewModel.showingLeaveConfirmation = true
                } label: {
                    Label("Покинуть список", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        } label: {
            Image(systemName: list.isShared ? "person.2.fill" : "person.badge.plus")
        }
    }

    // MARK: - Quick Action Buttons

    private var quickActionButtons: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.presentAddTransaction(type: .income)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("Доход")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.green, in: RoundedRectangle(cornerRadius: 14))
            }

            Button {
                viewModel.presentAddTransaction(type: .expense)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.circle.fill")
                    Text("Расход")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.red, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

// MARK: - Item Card

private struct ItemCard: View {
    let item: Transaction
    let list: Account
    let onDelete: () -> Void

    private var amountString: String {
        let sign = item.type == .income ? "+" : "−"
        let value = Decimal(item.amountMinorUnits) / 100
        return "\(sign)\(value) \(list.currencyCode)"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.category?.icon ?? "circle.dashed")
                .font(.body)
                .foregroundStyle(item.type == .income ? .green : .red)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.body)
                    .foregroundStyle(.primary)

                Text(item.date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Text(amountString)
                .font(.headline)
                .foregroundStyle(item.type == .income ? .green : .red)
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contextMenu {
            if PermissionManager.shared.canDelete(item: item, in: list) {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Удалить", systemImage: "trash")
                }
            }
        }
    }
}
