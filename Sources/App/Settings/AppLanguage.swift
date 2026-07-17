//
//  AppLanguage.swift
//  ShareBudget
//
//  Created by Danil on 17.07.2026.
//

import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case russian = "ru"
    case english = "en"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "Системный"
        case .russian: return "Русский"
        case .english: return "English"
        }
    }

    var locale: Locale? {
        switch self {
        case .system: return nil   // nil = использовать системную локаль устройства
        case .russian: return Locale(identifier: "ru")
        case .english: return Locale(identifier: "en")
        }
    }
}
