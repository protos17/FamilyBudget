//
//  CategoryListViewModel.swift
//  FamilyBudget
//
//  Created by Danil on 17.07.2026.
//

import SwiftUI
import SwiftData

@MainActor
final class CategoryListViewModel: ObservableObject {
    let account: Account

    @Published var editingCategory: Category?
    @Published var showingCreate = false

    private var modelContext: ModelContext?

    var categories: [Category] {
        account.sortedCategories
    }

    init(account: Account) {
        self.account = account
    }

    func attach(context: ModelContext) {
        self.modelContext = context
    }

    func deleteCategory(_ category: Category) {
        guard let modelContext else { return }
        DispatchQueue.main.async {
            modelContext.delete(category)
            try? modelContext.save()
        }
    }
}
