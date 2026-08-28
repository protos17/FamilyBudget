//
//  DateFormatter.swift
//  iShareBudget
//
//  Created by Danil on 29.08.2026.
//

import Foundation

struct DateHelper {
    private static let defaultFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "ru_RU")
        dateFormatter.dateFormat = "d MMMM yyyy"
        return dateFormatter
    }()
    
    static func getFormattedDate(from date: Date) -> String {
        defaultFormatter.string(from: date)
    }
}
