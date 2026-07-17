//
//  SymbolPickerView.swift
//  CloudKitSharing
//
//  Created by Danil on 17.07.2026.
//

import SwiftUI

struct SymbolPickerView: View {
    @Binding var selectedSymbol: String
    @Environment(\.dismiss) private var dismiss

    private let symbols = [
        "cart.fill", "fork.knife", "car.fill", "house.fill",
        "cross.case.fill", "gamecontroller.fill", "tshirt.fill", "airplane",
        "iphone", "graduationcap.fill", "lightbulb.fill", "pawprint.fill",
        "gift.fill", "cup.and.saucer.fill", "banknote.fill", "creditcard.fill",
        "briefcase.fill", "building.columns.fill", "film.fill", "sportscourt.fill",
        "doc.text.fill", "bus.fill", "leaf.fill", "drop.fill",
        "bolt.fill", "wifi", "phone.fill", "book.fill",
        "heart.fill", "figure.walk", "wrench.fill", "paintbrush.fill"
    ]
    private let columns = Array(repeating: GridItem(.flexible()), count: 5)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(symbols, id: \.self) { symbol in
                        Button {
                            selectedSymbol = symbol
                            dismiss()
                        } label: {
                            Image(systemName: symbol)
                                .font(.title2)
                                .frame(width: 44, height: 44)
                                .background(Color(.tertiarySystemFill), in: Circle())
                                .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("Выберите иконку")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
    }
}
