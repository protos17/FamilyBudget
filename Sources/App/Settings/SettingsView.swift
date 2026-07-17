//
//  SettingsView.swift
//  FamilyBudget
//
//  Created by Danil on 17.07.2026.
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @StateObject private var viewModel: SettingsViewModel
    @Environment(\.modelContext) private var modelContext
    @AppStorage("appAppearance") private var appAppearance = "system"

    init(account: Account) {
        _viewModel = StateObject(wrappedValue: SettingsViewModel(account: account))
    }

    var body: some View {
        Form {
            // MARK: - Счёт / бюджет
            Section {
                HStack {
                    Text("Название")
                    Spacer()
                    Text(viewModel.account.name)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Валюта")
                    Spacer()
                    Picker("", selection: currencyBinding) {
                        Text("RUB — ₽").tag("RUB")
                        Text("USD — $").tag("USD")
                        Text("EUR — €").tag("EUR")
                        Text("KZT — ₸").tag("KZT")
                    }
                    .labelsHidden()
                }
            } header: {
                Text("Бюджет")
            }

            // MARK: - Категории
            Section {
                Button {
                    viewModel.showingCategoryList = true
                } label: {
                    Label("Управление категориями", systemImage: "tag.fill")
                }
            }

            // MARK: - Семейный доступ
            Section {
                HStack {
                    Label("Статус", systemImage: "person.2.fill")
                    Spacer()
                    Text(viewModel.sharingStatusText)
                        .foregroundStyle(.secondary)
                }

                if viewModel.account.isShared,
                   PermissionManager.shared.canManageSharing(for: viewModel.account) {
                    NavigationLink("Управление участниками") {
                        // переиспользуй существующий CloudSharingView / экран управления шарингом
                        Text("Экран управления участниками")
                    }
                }

                if PermissionManager.shared.canLeaveList(viewModel.account) {
                    Button(role: .destructive) {
                        viewModel.showingLeaveConfirmation = true
                    } label: {
                        Label("Покинуть семейный бюджет", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .confirmationDialog(
                        "Покинуть \"\(viewModel.account.name)\"?",
                        isPresented: $viewModel.showingLeaveConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Покинуть", role: .destructive) {
                            Task {
                                try? await SharingManager.shared.leaveSharedList(viewModel.account, context: modelContext)
                            }
                        }
                    } message: {
                        Text("Вы потеряете доступ к этому семейному бюджету.")
                    }

                }
            } header: {
                Text("Семейный доступ")
            }

            // MARK: - Внешний вид
            Section {
                Picker("Тема", selection: $appAppearance) {
                    Text("Системная").tag("system")
                    Text("Светлая").tag("light")
                    Text("Тёмная").tag("dark")
                }
            } header: {
                Text("Внешний вид")
            }

            // MARK: - Уведомления
            Section {
                Toggle("Напоминания о бюджете", isOn: $viewModel.remindersEnabled)

                if viewModel.remindersEnabled {
                    DatePicker(
                        "Время напоминания",
                        selection: $viewModel.reminderTime,
                        displayedComponents: .hourAndMinute
                    )
                }
            } header: {
                Text("Уведомления")
            } footer: {
                Text("Ежедневное напоминание внести доходы и расходы за день.")
            }
            .alert("Уведомления отключены", isPresented: $viewModel.showingPermissionDeniedAlert) {
                Button("Открыть настройки") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Чтобы получать напоминания, разрешите уведомления в настройках устройства.")
            }


            // MARK: - Данные
            Section {
                Button {
                    viewModel.exportData()
                } label: {
                    Label("Экспортировать в CSV", systemImage: "square.and.arrow.up")
                }

                Button(role: .destructive) {
                    viewModel.showingResetConfirmation = true
                } label: {
                    Label("Удалить все операции", systemImage: "trash")
                }
                .confirmationDialog(
                    "Удалить все операции?",
                    isPresented: $viewModel.showingResetConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Удалить всё", role: .destructive) {
                        resetAllTransactions()
                    }
                } message: {
                    Text("Это действие необратимо. Категории и настройки останутся, все операции будут удалены.")
                }
            } header: {
                Text("Данные")
            }

            // MARK: - О приложении
            Section {
                HStack {
                    Text("Версия")
                    Spacer()
                    Text("\(viewModel.appVersion) (\(viewModel.buildNumber))")
                        .foregroundStyle(.secondary)
                }

                Link(destination: URL(string: "https://disk.yandex.ru/d/T4Uf88WJ8G7lmw")!) {
                    Label("Политика конфиденциальности", systemImage: "hand.raised.fill")
                }

                Link(destination: URL(string: "mailto:acerg751@mail.ru")!) {
                    Label("Написать в поддержку", systemImage: "envelope.fill")
                }
            } header: {
                Text("О приложении")
            }
        }
        .navigationTitle("Настройки")
        .sheet(isPresented: $viewModel.showingCategoryList) {
            NavigationStack {
                CategoryListView(account: viewModel.account)
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.exportedFileURL != nil },
            set: { if !$0 { viewModel.exportedFileURL = nil } }
        )) {
            if let url = viewModel.exportedFileURL {
                ShareSheet(activityItems: [url])
            }
        }
        .alert("Не удалось создать файл", isPresented: $viewModel.showingExportError) {
            Button("OK", role: .cancel) {}
        }
    }
    
    private var currencyBinding: Binding<String> {
        Binding(
            get: { viewModel.account.currencyCode },
            set: { newValue in
                viewModel.account.currencyCode = newValue
                try? modelContext.save()
            }
        )
    }

    private func exportData() {
        // Точка расширения: собрать CSV из account.transactions и показать UIActivityViewController
    }

    private func resetAllTransactions() {
        for transaction in viewModel.account.transactions ?? [] {
            modelContext.delete(transaction)
        }
        try? modelContext.save()
    }
}
