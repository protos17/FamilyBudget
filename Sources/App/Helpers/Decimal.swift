//
//  Decimal.swift
//  FamilyBudget
//
//  Created by Danil on 17.07.2026.
//

import Foundation

extension Decimal {
    func formattedAsCurrency(code: String) -> String {
        let formatter = NumberFormatter.currency(code: code)
        return formatter.string(from: self as NSDecimalNumber) ?? "\(self) \(code)"
    }
}
