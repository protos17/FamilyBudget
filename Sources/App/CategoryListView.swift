//
//  CategoryListView.swift
//  FamilyBudget
//
//  Created by Danil on 17.07.2026.
//

import SwiftUI

struct CategoryListView: View {
    let account: Account
    @Environment(\.modelContext) private var modelContext
    @State private var editingCategory: Category?
    @State private var showingCreate = false

    var body: some View {
        List {
            ForEach(account.categories ?? []) { category in
                HStack {
                    Image(systemName: category.icon)
                        .foregroundStyle(Color(hex: category.colorHex))
                        .frame(width: 28)
                    Text(category.name)
                }
                .contentShape(Rectangle())
                .onTapGesture { editingCategory = category }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        deleteCategory(category)
                    } label: {
                        Label("Удалить", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Категории")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingCreate = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingCreate) {
            CreateCategoryView(account: account, kind: .universal, onSave: { _ in })
        }
        .sheet(item: $editingCategory) { category in
            CreateCategoryView(
                account: account,
                kind: category.kind,
                editingCategory: category,
                onSave: { _ in }
            )
        }
    }

    private func deleteCategory(_ category: Category) {
        modelContext.delete(category)
        try? modelContext.save()
    }
}
