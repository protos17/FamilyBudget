//
//  CSVExporter.swift
//  FamilyBudget
//
//  Created by Danil on 17.07.2026.
//

import Foundation

enum CSVExporter {
    static func generateCSV(for account: Account) -> String {
        var lines = ["Дата;Тип;Название;Категория;Сумма;Валюта;Способ оплаты;Кто добавил;Заметка"]

        let transactions = (account.transactions ?? []).sorted { $0.date > $1.date }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd.MM.yyyy HH:mm"

        for item in transactions {
            let date = dateFormatter.string(from: item.date)
            let type = item.type == .income ? "Доход" : "Расход"
            let title = escape(item.title)
            let category = escape(item.category?.name ?? "")
            let amount = "\(item.amount)"
            let currency = account.currencyCode
            let payment = paymentMethodLabel(item.paymentMethod)
            let author = escape(item.createdByDisplayName ?? "")
            let note = escape(item.note ?? "")

            let line = [date, type, title, category, amount, currency, payment, author, note]
                .joined(separator: ";")
            lines.append(line)
        }

        return lines.joined(separator: "\n")
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
    static func writeToTemporaryFile(for account: Account) -> URL? {
        let csv = generateCSV(for: account)

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
