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
import PhotosUI

struct ListDetailView: View {
    let list: Account
    @Environment(\.modelContext) private var modelContext
    @Query private var allItems: [Transaction]
    
    @StateObject private var viewModel: ListDetailViewModel
    @Environment(\.locale) private var locale
    
    @AppStorage("isAIConnectionValid") private var isAIConnectionValid = false
    @AppStorage("isAIEnabled") private var isAIEnabled = false
    
    @State private var showingPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedPhotoData: Data?
    @State private var isRecognizing = false

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
    
    private var groupedItems: [(date: Date, items: [Transaction])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredItems) { item in
            calendar.startOfDay(for: item.date)
        }
        return grouped.sorted { $0.key > $1.key }.map { (date: $0.key, items: $0.value) }
    }
    
    private var summary: (income: Decimal, expense: Decimal) {
        viewModel.summary(for: filteredItems)
    }
    
    private var breakdownSlices: [CategoryBreakdownSlice] {
        viewModel.breakdownSlices(for: filteredItems)
    }
    
    private var canUseAIRecognition: Bool {
        isAIEnabled && isAIConnectionValid
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
            
            CategoryBreakdownChart(slices: breakdownSlices, currencyCode: list.currencyCode)
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
                ForEach(groupedItems, id: \.date) { group in
                    Section {
                        ForEach(group.items) { item in
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
                        }
                    } header: {
                        dateHeader(for: group.date)
                    }
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
                recognizedData: viewModel.recognizedPrefillData,
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
        .photosPicker(
            isPresented: $showingPhotoPicker,
            selection: $selectedPhotoItem,
            matching: .images
        )
        .onChange(of: selectedPhotoItem) { _, newItem in
            Task {
                if let newItem, let data = try? await newItem.loadTransferable(type: Data.self) {
                    selectedPhotoData = data
                    await recognizeTransactionFromPhoto(data: data)
                }
            }
        }
        .overlay {
            if isRecognizing {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white)
                        Text("Распознаю…")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                    .padding(32)
                    .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isRecognizing)
    }

    private func dateHeader(for date: Date) -> some View {
        let calendar = Calendar.current
        let isToday = calendar.isDateInToday(date)
        let isYesterday = calendar.isDateInYesterday(date)
        let isThisWeek = calendar.isDate(date, equalTo: .now, toGranularity: .weekOfYear)
        
        let text: String
        if isToday {
            text = String(localized: "Сегодня")
        } else if isYesterday {
            text = String(localized: "Вчера")
        } else if isThisWeek {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            formatter.locale = locale
            text = formatter.localizedString(for: date, relativeTo: .now)
        } else {
            text = DateHelper.getFormattedDate(from: date)
        }
        
        return Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
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
                    ForEach(list.sortedCategories) { category in
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
        VStack(spacing: 12) {
            if canUseAIRecognition {
                Button {
                    showingPhotoPicker = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "camera.viewfinder")
                        Text("Распознать по фото")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                }
            }
            
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
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }
    
    // MARK: - Photo Recognition
    
    private func recognizeTransactionFromPhoto(data: Data) async {
        isRecognizing = true
        defer { isRecognizing = false }
        
        selectedPhotoItem = nil
        selectedPhotoData = nil
        
        let expenseCategories = list.sortedCategories.filter {
            $0.kind == .expense || $0.kind == .universal
        }

        do {
            let result = try await AIReceiptRecognizer.recognize(
                imageData: data,
                expenseCategoryNames: expenseCategories.map(\.name)
            )
            viewModel.presentAddTransaction(recognized: result)
        } catch {
            viewModel.errorMessage = error.localizedDescription
            viewModel.showingError = true

            UserDefaults.standard.set(false, forKey: "isAIConnectionValid")
            NotificationCenter.default.post(name: GlobalSettingsViewModel.connectionInvalidatedNotification, object: nil)
        }
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

// MARK: - Preview

#Preview("Список с транзакциями") {
    let (container, account) = SampleData.createPreviewContainer()
    
    return NavigationStack {
        ListDetailView(list: account)
    }
    .modelContainer(container)
}

// MARK: - Sample Data for Preview

@MainActor
private enum SampleData {
    static func createPreviewContainer() -> (ModelContainer, Account) {
        let schema = Schema([
            Account.self,
            Transaction.self,
            Category.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        
        let account = createPreviewAccount()
        let foodCategory = createCategory(name: "Продукты", icon: "cart.fill", colorHex: "FF9500", kind: .expense)
        let salaryCategory = createCategory(name: "Зарплата", icon: "banknote.fill", colorHex: "34C759", kind: .income)
        let transportCategory = createCategory(name: "Транспорт", icon: "car.fill", colorHex: "007AFF", kind: .expense)
        let entertainmentCategory = createCategory(name: "Развлечения", icon: "film.fill", colorHex: "AF52DE", kind: .expense)
        let shoppingCategory = createCategory(name: "Покупки", icon: "bag.fill", colorHex: "FF2D55", kind: .expense)
        
        account.categories = [foodCategory, salaryCategory, transportCategory, entertainmentCategory, shoppingCategory]
        
        let calendar = Calendar.current
        let today = Date.now
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today)!
        let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: today)!
        let lastWeek = calendar.date(byAdding: .day, value: -7, to: today)!
        let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: today)!
        
        let transactions = [
            // Сегодня
            createTransaction(title: "Кофе", amountMinorUnits: 35000, type: .expense, date: today, category: foodCategory),
            createTransaction(title: "Обед", amountMinorUnits: 85000, type: .expense, date: today, category: foodCategory),
            createTransaction(title: "Метро", amountMinorUnits: 5700, type: .expense, date: today, category: transportCategory),
            // Вчера
            createTransaction(title: "Продукты", amountMinorUnits: 450000, type: .expense, date: yesterday, category: foodCategory),
            createTransaction(title: "Кино", amountMinorUnits: 120000, type: .expense, date: yesterday, category: entertainmentCategory),
            // 2 дня назад
            createTransaction(title: "Зарплата", amountMinorUnits: 15000000, type: .income, date: twoDaysAgo, category: salaryCategory),
            createTransaction(title: "Такси", amountMinorUnits: 45000, type: .expense, date: twoDaysAgo, category: transportCategory),
            // 3 дня назад
            createTransaction(title: "Одежда", amountMinorUnits: 890000, type: .expense, date: threeDaysAgo, category: shoppingCategory),
            createTransaction(title: "Ужин в ресторане", amountMinorUnits: 350000, type: .expense, date: threeDaysAgo, category: foodCategory),
            // Неделя назад
            createTransaction(title: "Бензин", amountMinorUnits: 250000, type: .expense, date: lastWeek, category: transportCategory),
            createTransaction(title: "Подписка", amountMinorUnits: 29900, type: .expense, date: lastWeek, category: entertainmentCategory),
            // 2 недели назад
            createTransaction(title: "Подарок", amountMinorUnits: 500000, type: .expense, date: twoWeeksAgo, category: shoppingCategory),
            createTransaction(title: "Фриланс", amountMinorUnits: 750000, type: .income, date: twoWeeksAgo, category: salaryCategory)
        ]
        
        for transaction in transactions {
            transaction.account = account
            container.mainContext.insert(transaction)
        }
        
        container.mainContext.insert(account)
        try? container.mainContext.save()
        
        return (container, account)
    }
    
    static func createPreviewAccount() -> Account {
        let account = Account(
            id: UUID(),
            name: "Основной бюджет",
            icon: "wallet.pass",
            colorHex: "007AFF"
        )
        account.currencyCode = "RUB"
        account.isShared = false
        return account
    }
    
    static func createCategory(name: String, icon: String, colorHex: String, kind: CategoryKind) -> Category {
        let category = Category(
            id: UUID(),
            name: name,
            icon: icon,
            colorHex: colorHex,
            kind: kind
        )
        return category
    }
    
    static func createTransaction(title: String, amountMinorUnits: Int, type: TransactionType, date: Date, category: Category?) -> Transaction {
        let transaction = Transaction(
            id: UUID(),
            title: title,
            amountMinorUnits: amountMinorUnits,
            type: type,
            date: date,
            createdByUserID: "current-user"
        )
        transaction.category = category
        return transaction
    }
}
