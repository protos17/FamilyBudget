//
//  BudgetSettingsView.swift
//  ShareBudget
//
//  Created by Danil on 17.07.2026.
//

import SwiftUI
import SwiftData

struct BudgetSettingsView: View {
    @StateObject private var viewModel: SettingsViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    
    init(account: Account) {
        _viewModel = StateObject(wrappedValue: SettingsViewModel(account: account))
    }
    
    var body: some View {
        Form {
            // MARK: - Бюджет
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
            
            // MARK: - Данные
            Section {
                Button {
                    viewModel.exportData(locale: locale)
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
        }
        .navigationTitle("Настройки бюджета")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Готово") { dismiss() }
            }
        }
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
    
    private func resetAllTransactions() {
        for transaction in viewModel.account.transactions ?? [] {
            modelContext.delete(transaction)
        }
        try? modelContext.save()
    }
}
