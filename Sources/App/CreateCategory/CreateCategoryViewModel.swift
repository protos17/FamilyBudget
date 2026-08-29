//
//  CreateCategoryViewModel.swift
//  CloudKitSharing
//
//  Created by Danil on 17.07.2026.
//

import SwiftUI
import SwiftData

@MainActor
final class CreateCategoryViewModel: ObservableObject {
    let account: Account
    let kind: CategoryKind
    let editingCategory: Category?
    let onSave: (Category) -> Void

    @Published var name: String
    @Published var icon: String
    @Published var colorHex: String
    @Published var showingSymbolPicker = false

    private var modelContext: ModelContext?

    var isEditing: Bool { editingCategory != nil }

    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var navigationTitleText: LocalizedStringKey {
        isEditing ? "Редактировать категорию" : "Новая категория"
    }

    var saveButtonText: LocalizedStringKey {
        isEditing ? "Сохранить" : "Создать"
    }

    init(
        account: Account,
        kind: CategoryKind,
        editingCategory: Category?,
        onSave: @escaping (Category) -> Void
    ) {
        self.account = account
        self.kind = kind
        self.editingCategory = editingCategory
        self.onSave = onSave
        self.name = editingCategory?.name ?? ""
        self.icon = editingCategory?.icon ?? "tag.fill"
        self.colorHex = editingCategory?.colorHex ?? "007AFF"
    }

    func attach(context: ModelContext) {
        self.modelContext = context
    }

    func save() {
        guard let modelContext else { return }

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
    }
}
