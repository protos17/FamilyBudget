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
    @Query private var allItems: [Transaction]
    
    @StateObject private var viewModel: ListDetailViewModel
    
    private var permissions: PermissionManager { .shared }
    
    init(list: Account) {
        self.list = list
        let listID = list.id
        _allItems = Query(
            filter: #Predicate<Transaction> { $0.account?.id == listID },
            sort: \.date,
            order: .reverse
        )
        _viewModel = StateObject(wrappedValue: ListDetailViewModel(list: list))
    }
    
    private var filteredItems: [Transaction] {
        viewModel.filteredItems(from: allItems)
    }
    
    private var summary: (income: Decimal, expense: Decimal) {
        viewModel.summary(for: filteredItems)
    }
    
    private var breakdownSlices: [CategoryBreakdownSlice] {
        viewModel.breakdownSlices(for: filteredItems)
    }
    
    var body: some View {
        List {
            if list.isShared {
                sharingBanner
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
            }
            
            MonthNavigator(selectedMonth: $viewModel.selectedMonth)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
            
            SummaryHeaderView(
                income: summary.income,
                expense: summary.expense,
                currencyCode: list.currencyCode
            )
            .nativeCard()
            .padding(.horizontal)
            
            CategoryBreakdownChart(slices: breakdownSlices)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 12, trailing: 0))
            
            filterBar
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
            
            if filteredItems.isEmpty {
                ContentUnavailableView(
                    "Нет операций",
                    systemImage: "creditcard",
                    description: Text("За выбранный месяц и фильтры операций не найдено")
                )
                .listRowSeparator(.hidden)
            } else {
                ForEach(filteredItems) { item in
                    ItemCard(item: item, list: list)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard permissions.canEdit(item: item, in: list) else { return }
                            viewModel.presentEditTransaction(item)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if permissions.canDelete(item: item, in: list) {
                                Button(role: .destructive) {
                                    viewModel.deleteItem(item)
                                } label: {
                                    Label("Удалить", systemImage: "trash")
                                }
                            }
                        }
                        .listRowSeparator(.visible)
                }
            }
        }
        .listStyle(.plain)
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            if permissions.canAddItem(to: list) {
                quickActionButtons
            }
        }
        .navigationTitle(list.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 16) {
                    shareButton
                    Button {
                        viewModel.showingBudgetSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $viewModel.showingBudgetSettings) {
            NavigationStack {
                BudgetSettingsView(account: list)
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
                editingTransaction: viewModel.editingTransaction,
                onSaveNew: { newItem in
                    viewModel.saveNewItem(newItem)
                },
                onSaveEdit: {
                    viewModel.saveEditedItem()
                }
            )
        }
        .sheet(isPresented: $viewModel.showingCreateCategory) {
            CreateCategoryView(
                account: list,
                kind: CategoryKind(matching: viewModel.categoryCreationKind),
                onSave: { _ in }
            )
        }
        .sheet(isPresented: $viewModel.showingShareInvite) {
            NavigationStack {
                ShareInviteView(account: list, viewModel: viewModel)
            }
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
        .padding(.horizontal)
        .frame(height: 44)
    }
    
    // MARK: - Filter bar
    
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Button("Все типы") { viewModel.selectedType = nil }
                    Button("Доход") { viewModel.selectedType = .income }
                        .background(Color.green, in: RoundedRectangle(cornerRadius: 14))
                        .shadow(color: Color.green.opacity(0.35), radius: 8, x: 0, y: 4)
                    Button("Расход") { viewModel.selectedType = .expense }
                        .background(Color.red, in: RoundedRectangle(cornerRadius: 14))
                        .shadow(color: Color.red.opacity(0.35), radius: 8, x: 0, y: 4)
                } label: {
                    filterChip(
                        label: viewModel.selectedType.map { $0 == .income ? Text("Доход") : Text("Расход") } ?? Text("Тип"),
                        isActive: viewModel.selectedType != nil
                    )
                }
                .buttonStyle(.plain)
                
                Menu {
                    Button("Все категории") { viewModel.selectedCategory = nil }
                    ForEach(list.categories ?? []) { category in
                        Button(category.name, systemImage: category.icon) {
                            viewModel.selectedCategory = category
                        }
                    }
                } label: {
                    filterChip(
                        label: viewModel.selectedCategory.map { Text($0.name) } ?? Text("Категория"),
                        isActive: viewModel.selectedCategory != nil
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
        }
    }
    
    private func filterChip(label: Text, isActive: Bool) -> some View {
        label
            .font(.subheadline)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minWidth: 90)
            .background(
                isActive ? Color.accentColor.opacity(0.15) : Color(.tertiarySystemFill),
                in: Capsule()
            )
            .foregroundStyle(isActive ? Color.accentColor : .primary)
    }
    
    
    // MARK: - Share Button
    
    private var shareButton: some View {
        Button {
            viewModel.showingShareInvite = true
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
    
    private var tintColor: Color {
        if let hex = item.category?.colorHex {
            return Color(hex: hex)
        }
        return item.type == .income ? .green : .red
    }
    
    private var symbolName: String {
        item.category?.icon ?? (item.type == .income ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
    }
    
    private var amountString: String {
        let sign = item.type == .income ? "+" : "−"
        return "\(sign)\(item.amount.formattedAsCurrency(code: list.currencyCode))"
    }
    
    private var authorName: String {
        item.createdByUserID == UserIdentityService.shared.currentUserID
        ? "Вы"
        : (item.createdByDisplayName ?? "Участник")
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbolName)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(tintColor)
                .frame(width: 40, height: 40)
                .background(tintColor.opacity(0.15), in: Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                
                HStack(spacing: 6) {
                    if let category = item.category {
                        Text(category.name)
                    }
                    Text("· \(authorName)")
                    Text("· \(item.date.formatted(date: .abbreviated, time: .omitted))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            
            Spacer(minLength: 0)
            
            Text(amountString)
                .font(.headline)
                .foregroundStyle(tintColor)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }
}


extension CategoryKind {
    func matches(_ type: TransactionType) -> Bool {
        switch (self, type) {
        case (.income, .income), (.expense, .expense):
            return true
        default:
            return false
        }
    }
    
    init(matching type: TransactionType) {
        self = type == .income ? .income : .expense
    }
}
