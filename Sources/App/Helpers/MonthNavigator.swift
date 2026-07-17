//
//  MonthNavigator.swift
//  CloudKitSharing
//
//  Created by Danil on 17.07.2026.
//

import SwiftUI

struct MonthNavigator: View {
    @Binding var selectedMonth: Date
    @Environment(\.locale) private var locale
    
    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        formatter.locale = locale
        return formatter.string(from: selectedMonth).capitalized
    }
    
    var body: some View {
        HStack {
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            Text(monthTitle)
                .font(.headline)
            
            Spacer()
            
            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(isCurrentMonth)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    private var isCurrentMonth: Bool {
        Calendar.current.isDate(selectedMonth, equalTo: .now, toGranularity: .month)
    }
    
    private func shiftMonth(by value: Int) {
        guard let newDate = Calendar.current.date(byAdding: .month, value: value, to: selectedMonth) else { return }
        selectedMonth = newDate
    }
}
