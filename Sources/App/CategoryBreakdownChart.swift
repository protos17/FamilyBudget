//
//  CategoryBreakdownChart.swift
//  CloudKitSharing
//
//  Created by Danil on 17.07.2026.
//

import SwiftUI
import Charts

struct CategoryBreakdownSlice: Identifiable {
    let id = UUID()
    let categoryName: String
    let emoji: String
    let amount: Double
    let percentage: Double
    let colorHex: String
}

struct CategoryBreakdownChart: View {
    let slices: [CategoryBreakdownSlice]
    @State private var showingAll = false

    private var visibleSlices: [CategoryBreakdownSlice] {
        showingAll ? slices : Array(slices.prefix(5))
    }

    var body: some View {
        if slices.isEmpty {
            ContentUnavailableView(
                "Нет расходов",
                systemImage: "chart.pie",
                description: Text("За выбранный месяц расходов не найдено")
            )
            .frame(height: 200)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Расходы по категориям")
                    .font(.headline)
                    .padding(.horizontal)

                Chart(slices) { slice in
                    SectorMark(
                        angle: .value("Сумма", slice.amount),
                        innerRadius: .ratio(0.6),
                        angularInset: 1.5
                    )
                    .foregroundStyle(Color(hex: slice.colorHex))
                    .cornerRadius(4)
                    .annotation(position: .overlay) {
                        if slice.percentage >= 6 {
                            Text(String(format: "%.0f%%", slice.percentage))
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                        }
                    }
                }
                .frame(height: 220)
                .padding(.horizontal)

                VStack(spacing: 10) {
                    ForEach(visibleSlices) { slice in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color(hex: slice.colorHex))
                                .frame(width: 10, height: 10)
                            Text(slice.categoryName)
                                .font(.subheadline)
                            Spacer()
                            Text(String(format: "%.0f%%", slice.percentage))
                                .font(.subheadline.bold())
                                .foregroundStyle(.secondary)
                        }
                    }

                    if slices.count > 5 {
                        Button {
                            withAnimation(.snappy) { showingAll.toggle() }
                        } label: {
                            Text(showingAll ? "Скрыть" : "Показать все")
                                .font(.subheadline.weight(.medium))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
            )
            .padding(.horizontal)
        }
    }
}
