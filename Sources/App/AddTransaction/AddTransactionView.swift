//
//  AddTransactionView.swift
//  CloudKitSharing
//
//  Created by Danil on 17.07.2026.
//

import SwiftUI

struct AddTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: AddTransactionViewModel
    @FocusState private var amountFieldFocused: Bool

    init(account: Account, prefilledType: TransactionType, onSave: @escaping (Transaction) -> Void) {
        _viewModel = StateObject(
            wrappedValue: AddTransactionViewModel(account: account, prefilledType: prefilledType, onSave: onSave)
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Тип", selection: $viewModel.type) {
                        Text("Доход").tag(TransactionType.income)
                        Text("Расход").tag(TransactionType.expense)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    HStack {
                        Text(viewModel.account.currencyCode)
                            .foregroundStyle(.secondary)
                        TextField("0", text: $viewModel.amountText)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .focused($amountFieldFocused)
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Сумма")
                }

                Section {
                    TextField("Название", text: $viewModel.title)

                    Picker("Категория", selection: $viewModel.selectedCategory) {
                        Text("Без категории").tag(Category?.none)
                        ForEach(viewModel.categories) { category in
                            Label(category.name, systemImage: category.icon)
                                .tag(Category?.some(category))
                        }
                    }

                    DatePicker("Дата", selection: $viewModel.date, displayedComponents: [.date, .hourAndMinute])

                    Picker("Способ оплаты", selection: $viewModel.paymentMethod) {
                        Text("Карта").tag(PaymentMethod.card)
                        Text("Наличные").tag(PaymentMethod.cash)
                        Text("Перевод").tag(PaymentMethod.transfer)
                        Text("Другое").tag(PaymentMethod.other)
                    }
                }

                Section {
                    TextField("Заметка (необязательно)", text: $viewModel.note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(viewModel.type == .income ? "Новый доход" : "Новый расход")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        if viewModel.save() {
                            dismiss()
                        }
                    }
                    .disabled(!viewModel.canSave)
                    .fontWeight(.semibold)
                }
            }
            .alert("Введите корректную сумму", isPresented: $viewModel.showingValidationError) {
                Button("OK", role: .cancel) {}
            }
            .onAppear { amountFieldFocused = true }
        }
    }
}
