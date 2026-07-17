//
//  SummaryHeaderView.swift
//  CloudKitSharing
//
//  Created by Danil on 17.07.2026.
//

import SwiftUI

struct SummaryHeaderView: View {
    let income: Decimal
    let expense: Decimal
    let currencyCode: String
    
    private var balance: Decimal { income - expense }
    
    var body: some View {
        HStack(spacing: 0) {
            summaryColumn(title: "Доход", value: income, color: .green)
            Divider().frame(height: 36)
            summaryColumn(title: "Расход", value: expense, color: .red)
            Divider().frame(height: 36)
            summaryColumn(title: "Баланс", value: balance, color: balance >= 0 ? .primary : .red)
        }
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
    }
    
    private func summaryColumn(title: LocalizedStringKey, value: Decimal, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value.formattedAsCurrency(code: currencyCode))
                .font(.subheadline.bold())
                .foregroundStyle(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

extension View {
    func nativeCard(cornerRadius: CGFloat = 16) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
            )
    }
}
