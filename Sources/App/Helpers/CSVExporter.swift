//
//  CSVExporter.swift
//  FamilyBudget
//
//  Created by Danil on 17.07.2026.
//

import Foundation

enum CSVExporter {
    static func generateCSV(for account: Account, locale: Locale) -> String {
        let header = [
            String(localized: "Дата", locale: locale),
            String(localized: "Тип", locale: locale),
            String(localized: "Название", locale: locale),
            String(localized: "Категория", locale: locale),
            String(localized: "Сумма", locale: locale),
            String(localized: "Валюта", locale: locale),
            String(localized: "Способ оплаты", locale: locale),
            String(localized: "Кто добавил", locale: locale),
            String(localized: "Заметка", locale: locale)
        ].joined(separator: ";")

        var lines = [header]

        let transactions = (account.transactions ?? []).sorted { $0.date > $1.date }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd.MM.yyyy HH:mm"
        dateFormatter.locale = locale

        for item in transactions {
            let date = dateFormatter.string(from: item.date)
            let type = item.type == .income
                ? String(localized: "Доход", locale: locale)
                : String(localized: "Расход", locale: locale)
            let title = escape(item.title)
            let category = escape(item.category?.name ?? "")
            let amount = "\(item.amount)"
            let currency = account.currencyCode
            let payment = paymentMethodLabel(item.paymentMethod, locale: locale)
            let author = escape(item.createdByDisplayName ?? "")
            let note = escape(item.note ?? "")

            let line = [date, type, title, category, amount, currency, payment, author, note]
                .joined(separator: ";")
            lines.append(line)
        }

        return lines.joined(separator: "\n")
    }

    private static func paymentMethodLabel(_ method: PaymentMethod, locale: Locale) -> String {
        switch method {
        case .cash: return String(localized: "Наличные", locale: locale)
        case .card: return String(localized: "Карта", locale: locale)
        case .transfer: return String(localized: "Перевод", locale: locale)
        case .other: return String(localized: "Другое", locale: locale)
        }
    }
    /// Экранирование значений с точкой с запятой, кавычками или переносом строки
    private static func escape(_ value: String) -> String {
        guard value.contains(";") || value.contains("\"") || value.contains("\n") else {
            return value
        }
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
    
    private static func paymentMethodLabel(_ method: PaymentMethod) -> String {
        switch method {
        case .cash: return "Наличные"
        case .card: return "Карта"
        case .transfer: return "Перевод"
        case .other: return "Другое"
        }
    }
    
    /// Пишет CSV во временный файл и возвращает URL для шаринга
    static func writeToTemporaryFile(for account: Account, locale: Locale) -> URL? {
        let csv = generateCSV(for: account, locale: locale)
        
        // BOM для корректного открытия кириллицы в Excel
        let bom = "\u{FEFF}"
        let content = bom + csv
        
        let fileName = "\(account.name)_\(dateStamp()).csv"
        let sanitizedFileName = fileName.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(sanitizedFileName)
        
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
    
    private static func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: .now)
    }
}
