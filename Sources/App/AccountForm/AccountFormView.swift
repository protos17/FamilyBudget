//
//  AccountFormView.swift
//  FamilyBudget
//
//  Created by Danil on 17.07.2026.
//

import SwiftUI
import SwiftData

struct AccountFormView: View {
    @StateObject private var viewModel: AccountFormViewModel
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    private static let icons = [
        "creditcard.fill", "house.fill", "car.fill", "airplane",
        "banknote.fill", "cart.fill", "gift.fill", "briefcase.fill",
        "building.columns.fill", "heart.fill", "graduationcap.fill", "wallet.pass.fill",
        "star.fill", "leaf.fill", "pawprint.fill", "figure.2.and.child.holdinghands"
    ]
    
    init(editingAccount: Account? = nil,
         duplicateFrom: Account? = nil,
         onSave: @escaping (Account) -> Void) {
        _viewModel = StateObject(wrappedValue: AccountFormViewModel(
            editingAccount: editingAccount,
            duplicateFrom: duplicateFrom,
            onSave: onSave
        ))
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AccountIconPreview(icon: viewModel.icon, colorHex: viewModel.colorHex) {
                        viewModel.showingSymbolPicker = true
                    }
                }
                
                Section {
                    TextField("Название бюджета", text: $viewModel.name)
                }
                
                Section("Иконка") {
                    AccountIconGrid(icons: Self.icons, selectedIcon: $viewModel.icon, colorHex: viewModel.colorHex)
                }
                
                Section("Цвет") {
                    AccountColorGrid(colors: ColorPalette.all, selectedColor: $viewModel.colorHex)
                }
                
                Section("Валюта") {
                    AccountCurrencyPicker(currencyCode: $viewModel.currencyCode)
                }
            }
            .navigationTitle(viewModel.navigationTitleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(viewModel.isEditing ? "Сохранить" : "Создать") {
                        viewModel.save()
                        dismiss()
                    }
                    .disabled(!viewModel.canSave)
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $viewModel.showingSymbolPicker) {
                SymbolPickerView(selectedSymbol: $viewModel.icon)
            }
        }
        .onAppear {
            viewModel.attach(context: modelContext)
        }
    }
}

private struct AccountIconPreview: View {
    let icon: String
    let colorHex: String
    let onTap: () -> Void
    
    var body: some View {
        HStack {
            Spacer()
            Button(action: onTap) {
                Image(systemName: icon)
                    .font(.system(size: 36))
                    .frame(width: 84, height: 84)
                    .background(Color(hex: colorHex).opacity(0.15), in: Circle())
                    .foregroundStyle(Color(hex: colorHex))
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.vertical, 8)
        .listRowBackground(Color.clear)
    }
}

private struct AccountIconGrid: View {
    let icons: [String]
    @Binding var selectedIcon: String
    let colorHex: String
    
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 14) {
            ForEach(icons, id: \.self) { symbol in
                Image(systemName: symbol)
                    .font(.title3)
                    .frame(width: 40, height: 40)
                    .background(
                        selectedIcon == symbol
                        ? Color(hex: colorHex).opacity(0.2)
                        : Color(.tertiarySystemFill),
                        in: Circle()
                    )
                    .foregroundStyle(selectedIcon == symbol ? Color(hex: colorHex) : .primary)
                    .onTapGesture { selectedIcon = symbol }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct AccountColorGrid: View {
    let colors: [String]
    @Binding var selectedColor: String
    
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 14) {
            ForEach(colors, id: \.self) { hex in
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: 30, height: 30)
                    .overlay {
                        if selectedColor == hex {
                            Circle().strokeBorder(.primary, lineWidth: 2)
                        }
                    }
                    .onTapGesture { selectedColor = hex }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct AccountCurrencyPicker: View {
    @Binding var currencyCode: String
    
    var body: some View {
        Picker("Валюта", selection: $currencyCode) {
            Text("₽ Рубль").tag("RUB")
            Text("$ Доллар").tag("USD")
            Text("€ Евро").tag("EUR")
            Text("₸ Тенге").tag("KZT")
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }
}
