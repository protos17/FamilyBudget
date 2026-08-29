//
//  CreateCategoryView.swift
//  CloudKitSharing
//
//  Created by Danil on 17.07.2026.
//

import SwiftUI
import SwiftData

struct CreateCategoryView: View {
    @StateObject private var viewModel: CreateCategoryViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    init(
        account: Account,
        kind: CategoryKind,
        editingCategory: Category? = nil,
        onSave: @escaping (Category) -> Void
    ) {
        _viewModel = StateObject(wrappedValue: CreateCategoryViewModel(
            account: account,
            kind: kind,
            editingCategory: editingCategory,
            onSave: onSave
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Button {
                            viewModel.showingSymbolPicker = true
                        } label: {
                            Image(systemName: viewModel.icon)
                                .font(.system(size: 28))
                                .frame(width: 56, height: 56)
                                .background(Color(hex: viewModel.colorHex).opacity(0.15), in: Circle())
                                .foregroundStyle(Color(hex: viewModel.colorHex))
                        }
                        .buttonStyle(.plain)

                        TextField("Название категории", text: $viewModel.name)
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
                                        if viewModel.colorHex == hex {
                                            Circle().strokeBorder(.primary, lineWidth: 2)
                                        }
                                    }
                                    .onTapGesture { viewModel.colorHex = hex }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 170)
                }
            }

            .navigationTitle(viewModel.navigationTitleText)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(viewModel.saveButtonText) {
                        viewModel.save()
                        dismiss()
                    }
                    .disabled(!viewModel.canSave)
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
