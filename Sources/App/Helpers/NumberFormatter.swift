//
//  Formatter.swift
//  FamilyBudget
//
//  Created by Danil on 17.07.2026.
//

import Foundation

extension NumberFormatter {
    nonisolated(unsafe) private static var cache: [String: NumberFormatter] = [:]

    static func currency(code: String) -> NumberFormatter {
        if let cached = cache[code] {
            return cached
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale.current
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.roundingMode = .floor
        formatter.currencyCode = code
        formatter.currencySymbol = symbol(for: code)

        cache[code] = formatter
        return formatter
    }

    private static func symbol(for code: String) -> String {
        switch code {
        case "RUB": return "₽"
        case "USD": return "$"
        case "EUR": return "€"
        case "KZT": return "₸"
        default: return code
        }
    }
}
