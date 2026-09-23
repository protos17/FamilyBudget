//
//  MonthNavigator.swift
//  CloudKitSharing
//
//  Created by Danil on 17.07.2026.
//

import SwiftUI

struct MonthNavigator: View {
    @Binding var selectedMonth: Date
    var onTitleTapped: (() -> Void)? = nil
    @Environment(\.locale) private var locale
    
    @State private var showingInternalPicker = false
    
    init(selectedMonth: Binding<Date>, onTitleTapped: (() -> Void)? = nil) {
        self._selectedMonth = selectedMonth
        self.onTitleTapped = onTitleTapped
    }
    
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
            
            Button {
                if let onTitleTapped {
                    onTitleTapped()
                } else {
                    showingInternalPicker = true
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.subheadline)
                        .foregroundStyle(Color.accentColor)
                    Text(monthTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemFill), in: Capsule())
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(isCurrentOrFutureMonth)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .sheet(isPresented: $showingInternalPicker) {
            MonthDatePickerSheet(selectedMonth: $selectedMonth)
        }
    }
    
    private var isCurrentOrFutureMonth: Bool {
        Calendar.current.isDate(selectedMonth, equalTo: .now, toGranularity: .month) || selectedMonth > .now
    }
    
    private func shiftMonth(by value: Int) {
        guard let newDate = Calendar.current.date(byAdding: .month, value: value, to: selectedMonth) else { return }
        selectedMonth = newDate
    }
}

struct MonthDatePickerSheet: View {
    @Binding var selectedMonth: Date
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    
    @State private var pickerDate: Date
    @State private var selectedMonthIndex: Int
    @State private var selectedYear: Int
    @State private var pickerMode: PickerMode = .monthYear
    @State private var isCancelled = false
    
    enum PickerMode: String, CaseIterable, Identifiable {
        case monthYear = "Месяц и год"
        case calendar = "Календарь"
        
        var id: String { rawValue }
    }
    
    init(selectedMonth: Binding<Date>) {
        self._selectedMonth = selectedMonth
        let initialDate = selectedMonth.wrappedValue
        self._pickerDate = State(initialValue: initialDate)
        let cal = Calendar.current
        self._selectedMonthIndex = State(initialValue: cal.component(.month, from: initialDate))
        self._selectedYear = State(initialValue: cal.component(.year, from: initialDate))
    }
    
    private var monthSymbols: [String] {
        let formatter = DateFormatter()
        formatter.locale = locale
        let symbols = formatter.standaloneMonthSymbols ?? formatter.monthSymbols ?? []
        return symbols.map(\.capitalized)
    }
    
    private var availableYears: [Int] {
        let currentYear = Calendar.current.component(.year, from: .now)
        let minYear = min(2015, selectedYear - 1)
        let maxYear = max(currentYear + 2, selectedYear + 1)
        return Array(minYear...maxYear)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Picker("Режим выбора", selection: $pickerMode) {
                    ForEach(PickerMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                
                Group {
                    switch pickerMode {
                    case .monthYear:
                        monthYearWheels
                    case .calendar:
                        calendarPicker
                    }
                }
                .frame(maxWidth: .infinity)
                
                quickActions
                
                Spacer()
            }
            .navigationTitle("Выбор месяца")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        isCancelled = true
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        applySelection()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onDisappear {
                if !isCancelled {
                    applySelection()
                }
            }
        }
        .presentationDetents([.height(490), .large])
        .presentationDragIndicator(.visible)
    }
    
    private var monthYearWheels: some View {
        HStack(spacing: 0) {
            Picker("Месяц", selection: $selectedMonthIndex) {
                ForEach(1...12, id: \.self) { month in
                    let name = month <= monthSymbols.count ? monthSymbols[month - 1] : "\(month)"
                    Text(name).tag(month)
                }
            }
            .pickerStyle(.wheel)
            .onChange(of: selectedMonthIndex) { _, newMonth in
                updatePickerDate(month: newMonth, year: selectedYear)
            }
            
            Picker("Год", selection: $selectedYear) {
                ForEach(availableYears, id: \.self) { year in
                    Text(verbatim: "\(year)").tag(year)
                }
            }
            .pickerStyle(.wheel)
            .onChange(of: selectedYear) { _, newYear in
                updatePickerDate(month: selectedMonthIndex, year: newYear)
            }
        }
        .frame(height: 190)
        .padding(.horizontal)
    }
    
    private var calendarPicker: some View {
        DatePicker(
            "Выберите дату",
            selection: $pickerDate,
            displayedComponents: [.date]
        )
        .datePickerStyle(.graphical)
        .padding(.horizontal)
        .onChange(of: pickerDate) { _, newDate in
            let cal = Calendar.current
            let newMonth = cal.component(.month, from: newDate)
            let newYear = cal.component(.year, from: newDate)
            if newMonth != selectedMonthIndex {
                selectedMonthIndex = newMonth
            }
            if newYear != selectedYear {
                selectedYear = newYear
            }
        }
    }
    
    private var quickActions: some View {
        Button {
            let now = Calendar.current.startOfMonth(for: .now)
            pickerDate = now
            selectedMonth = now
            dismiss()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                Text("Текущий месяц")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }
    
    private func updatePickerDate(month: Int, year: Int) {
        let cal = Calendar.current
        let currentM = cal.component(.month, from: pickerDate)
        let currentY = cal.component(.year, from: pickerDate)
        guard currentM != month || currentY != year else { return }
        
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        if let newDate = cal.date(from: components) {
            pickerDate = newDate
        }
    }
    
    private func applySelection() {
        selectedMonth = Calendar.current.startOfMonth(for: pickerDate)
    }
}
