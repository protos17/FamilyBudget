//
//  CreateCategoryView.swift
//  CloudKitSharing
//
//  Created by Danil on 17.07.2026.
//

import SwiftUI

struct CreateCategoryView: View {
    let account: Account
    let kind: CategoryKind
    let editingCategory: Category?
    let onSave: (Category) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var name: String
    @State private var icon: String
    @State private var colorHex: String
    @State private var showingSymbolPicker = false
    
    init(
        account: Account,
        kind: CategoryKind,
        editingCategory: Category? = nil,
        onSave: @escaping (Category) -> Void
    ) {
        self.account = account
        self.kind = kind
        self.editingCategory = editingCategory
        self.onSave = onSave
        _name = State(initialValue: editingCategory?.name ?? "")
        _icon = State(initialValue: editingCategory?.icon ?? "tag.fill")
        _colorHex = State(initialValue: editingCategory?.colorHex ?? "007AFF")
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Button {
                            showingSymbolPicker = true
                        } label: {
                            Image(systemName: icon)
                                .font(.system(size: 28))
                                .frame(width: 56, height: 56)
                                .background(Color(hex: colorHex).opacity(0.15), in: Circle())
                                .foregroundStyle(Color(hex: colorHex))
                        }
                        .buttonStyle(.plain)
                        
                        TextField("Название категории", text: $name)
                    }
                    .padding(.vertical, 4)
                }
                
                Section("Цвет") {
                    ScrollView(.vertical, showsIndicators: false) {
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
                    .frame(maxHeight: 170)
                }
            }
            
            .navigationTitle(editingCategory == nil ? "Новая категория" : "Редактировать категорию")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editingCategory == nil ? "Создать" : "Сохранить") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showingSymbolPicker) {
                SymbolPickerView(selectedSymbol: $icon)
            }
        }
    }
    
    private func save() {
        if let existing = editingCategory {
            existing.name = name.trimmingCharacters(in: .whitespaces)
            existing.icon = icon
            existing.colorHex = colorHex
            try? modelContext.save()
            onSave(existing)
        } else {
            let category = Category(
                name: name.trimmingCharacters(in: .whitespaces),
                icon: icon,
                colorHex: colorHex,
                kind: kind
            )
            category.account = account
            modelContext.insert(category)
            try? modelContext.save()
            onSave(category)
        }
        dismiss()
    }
}
