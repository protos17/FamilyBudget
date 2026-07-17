//
//  AccountFormView.swift
//  FamilyBudget
//
//  Created by Danil on 17.07.2026.
//

import SwiftUI
import SwiftData

struct AccountFormView: View {
    let editingAccount: Account?
    let onSave: (Account) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var name: String
    @State private var icon: String
    @State private var colorHex: String
    @State private var currencyCode: String
    @State private var showingSymbolPicker = false
    
    private let icons = [
        "creditcard.fill", "house.fill", "car.fill", "airplane",
        "banknote.fill", "cart.fill", "gift.fill", "briefcase.fill",
        "building.columns.fill", "heart.fill", "graduationcap.fill", "wallet.pass.fill",
        "star.fill", "leaf.fill", "pawprint.fill", "figure.2.and.child.holdinghands"
    ]
    
    init(editingAccount: Account? = nil, onSave: @escaping (Account) -> Void) {
        self.editingAccount = editingAccount
        self.onSave = onSave
        _name = State(initialValue: editingAccount?.name ?? "")
        _icon = State(initialValue: editingAccount?.icon ?? "creditcard.fill")
        _colorHex = State(initialValue: editingAccount?.colorHex ?? ColorPalette.all[0])
        _currencyCode = State(initialValue: editingAccount?.currencyCode ?? "RUB")
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        Button {
                            showingSymbolPicker = true
                        } label: {
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
                
                Section {
                    TextField("Название бюджета", text: $name)
                }
                
                Section("Иконка") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 14) {
                        ForEach(icons, id: \.self) { symbol in
                            Image(systemName: symbol)
                                .font(.title3)
                                .frame(width: 40, height: 40)
                                .background(
                                    icon == symbol
                                    ? Color(hex: colorHex).opacity(0.2)
                                    : Color(.tertiarySystemFill),
                                    in: Circle()
                                )
                                .foregroundStyle(icon == symbol ? Color(hex: colorHex) : .primary)
                                .onTapGesture { icon = symbol }
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                Section("Цвет") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 14) {
                        ForEach(ColorPalette.all, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 30, height: 30)
                                .overlay {
                                    if colorHex == hex {
                                        Circle().strokeBorder(.primary, lineWidth: 2)
                                    }
                                }
                                .onTapGesture { colorHex = hex }
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                Section("Валюта") {
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
            .navigationTitle(editingAccount == nil ? "Новый бюджет" : "Редактировать бюджет")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editingAccount == nil ? "Создать" : "Сохранить") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingSymbolPicker) {
                SymbolPickerView(selectedSymbol: $icon)
            }
        }
    }
    
    private func save() {
        if let existing = editingAccount {
            existing.name = name.trimmingCharacters(in: .whitespaces)
            existing.icon = icon
            existing.colorHex = colorHex
            existing.currencyCode = currencyCode
            try? modelContext.save()
            onSave(existing)
        } else {
            let account = Account(name: name.trimmingCharacters(in: .whitespaces), currencyCode: currencyCode)
            account.icon = icon
            account.colorHex = colorHex
            modelContext.insert(account)
            try? modelContext.save()
            onSave(account)
        }
        dismiss()
    }
}
