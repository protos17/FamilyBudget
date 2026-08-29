//
//  CategoryListView.swift
//  FamilyBudget
//
//  Created by Danil on 17.07.2026.
//

import SwiftUI
import SwiftData

struct CategoryListView: View {
    @StateObject private var viewModel: CategoryListViewModel
    @Environment(\.modelContext) private var modelContext

    init(account: Account) {
        _viewModel = StateObject(wrappedValue: CategoryListViewModel(account: account))
    }

    var body: some View {
        List {
            ForEach(viewModel.categories) { category in
                HStack {
                    Image(systemName: category.icon)
                        .foregroundStyle(Color(hex: category.colorHex))
                        .frame(width: 28)
                    Text(category.name)
                }
                .contentShape(Rectangle())
                .onTapGesture { viewModel.editingCategory = category }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        viewModel.deleteCategory(category)
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
                    viewModel.showingCreate = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $viewModel.showingCreate) {
            CreateCategoryView(account: viewModel.account, kind: .universal, onSave: { _ in })
        }
        .sheet(item: $viewModel.editingCategory) { category in
            CreateCategoryView(
                account: viewModel.account,
                kind: category.kind,
                editingCategory: category,
                onSave: { _ in }
            )
        }
        .onAppear {
            viewModel.attach(context: modelContext)
        }
    }
}
