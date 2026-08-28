//
//  AIReceiptRecognizer.swift
//  FamilyBudget
//
//  Shared OpenAI-compatible vision API call for recognizing a receipt/photo
//  into transaction fields. Used both by the in-app "Распознать по фото"
//  flow and by the Share Extension import flow.
//

import UIKit

enum AIReceiptRecognizer {
    static func recognize(imageData: Data, expenseCategoryNames: [String]) async throws -> RecognizedTransactionData {
        let baseURL = UserDefaults.standard.string(forKey: "aiBaseURL") ?? "https://api.openai.com/v1"
        guard let apiKey = KeychainHelper.load(forKey: "aiAPIKey"), !apiKey.isEmpty else {
            throw RecognitionError.noAPIKey
        }
        let model = UserDefaults.standard.string(forKey: "aiModel") ?? "gpt-4o"

        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: "\(trimmedBaseURL)/chat/completions") else {
            throw RecognitionError.invalidURL
        }

        let compressedData = compressImage(imageData) ?? imageData
        let base64 = compressedData.base64EncodedString()

        let categoryNames = expenseCategoryNames.joined(separator: ", ")

        let systemPrompt = """
        Ты — помощник для распознавания финансовых операций по фото. \
        Проанализируй изображение (чек, скриншот оплаты, фото товара или услуги) \
        и извлеки данные об одной операции расхода.

        Доступные категории: [\(categoryNames)]

        Верни СТРОГО ТОЛЬКО JSON-объект, без markdown-разметки, без ```json, без пояснений, \
        со следующими полями:
        - "title": краткое описание операции (например "Кофе", "Продукты", "Такси")
        - "amount": сумма расхода как положительное число в основных единицах валюты (например 350.50, не в копейках)
        - "categoryName": название наиболее подходящей категории ТОЛЬКО из списка доступных (строка или null, если ни одна не подходит)
        - "paymentMethod": один из "card", "cash", "transfer", "other" (строка)
        - "date": дата операции с чека в формате "dd-MM-yyyy" (или "dd-MM-yyyy HH:mm", если видно время). \
            Если дата на чеке не найдена, верни null — НЕ подставляй сегодняшнюю дату сам.
        - "note": дополнительная информация или null

        Если на фото невозможно распознать финансовую операцию, верни JSON: {"error": "описание причины"}.
        """

        // Локальные OpenAI-совместимые серверы (LM Studio, llama.cpp, Ollama и т.п.)
        // часто не поддерживают response_format/detail — используем только
        // базовый набор полей, максимально совместимый с любым сервером.
        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": "Распознай операцию расхода по этому фото. Верни только JSON, без markdown."],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/jpeg;base64,\(base64)"
                            ]
                        ]
                    ]
                ]
            ],
            "max_tokens": 500,
            "temperature": 0.2
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RecognitionError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            var detail = "HTTP \(httpResponse.statusCode)"
            if let errorJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let errorObj = errorJSON["error"] as? [String: Any],
                   let message = errorObj["message"] as? String {
                    detail = message
                } else if let message = errorJSON["error"] as? String {
                    detail = message
                } else if let message = errorJSON["message"] as? String {
                    detail = message
                } else if let raw = String(data: data, encoding: .utf8), !raw.isEmpty {
                    detail = raw
                }
            } else if let raw = String(data: data, encoding: .utf8), !raw.isEmpty {
                detail = raw
            }
            #if DEBUG
            print("AIReceiptRecognizer error \(httpResponse.statusCode): \(detail)")
            #endif
            throw RecognitionError.apiError(statusCode: httpResponse.statusCode, message: detail)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw RecognitionError.parseError
        }

        guard let contentData = Self.extractJSONData(from: content) else {
            throw RecognitionError.parseError
        }

        if let parsed = try? JSONSerialization.jsonObject(with: contentData) as? [String: Any],
           let errorMessage = parsed["error"] as? String {
            throw RecognitionError.recognitionFailed(errorMessage)
        }

        do {
            return try JSONDecoder().decode(RecognizedTransactionData.self, from: contentData)
        } catch {
            throw RecognitionError.parseError
        }
    }

    /// Локальные модели (например Qwen2.5-VL) часто оборачивают JSON в ```json ... ```
    /// или добавляют пояснительный текст вокруг него. Эта функция вычленяет
    /// первый валидный JSON-объект из произвольного текстового ответа.
    private static func extractJSONData(from content: String) -> Data? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Быстрый путь: весь контент уже является JSON
        if let data = trimmed.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            return data
        }

        // Ищем содержимое между первой '{' и последней '}'
        if let firstBrace = trimmed.firstIndex(of: "{"),
           let lastBrace = trimmed.lastIndex(of: "}"),
           firstBrace < lastBrace {
            let substring = String(trimmed[firstBrace...lastBrace])
            if let data = substring.data(using: .utf8),
               (try? JSONSerialization.jsonObject(with: data)) != nil {
                return data
            }
        }

        return nil
    }

    private static func compressImage(_ data: Data, maxDimension: CGFloat = 1536) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let maxSide = max(image.size.width, image.size.height)
        guard maxSide > maxDimension else { return data }

        let scale = maxDimension / maxSide
        let newSize = CGSize(
            width: floor(image.size.width * scale),
            height: floor(image.size.height * scale)
        )

        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }
}

// MARK: - Recognition Data Model

struct RecognizedTransactionData: Codable {
    let title: String
    let amount: Double
    let categoryName: String?
    let paymentMethod: String?
    /// Дата операции с чека в формате "dd-MM-yyyy" или "dd-MM-yyyy HH:mm".
    /// Может отсутствовать, если модель не смогла её распознать.
    let date: String?
    let note: String?

    /// Парсит `date` в `Date`. Возвращает `nil`, если поле отсутствует
    /// или не соответствует ожидаемому формату — в таком случае вызывающий
    /// код должен сам подставить дефолт (например `.now`).
    var parsedDate: Date? {
        guard let date, !date.isEmpty else { return nil }

        let formatsToTry = ["dd-MM-yyyy", "dd-MM-yyyy HH:mm", "yyyy-MM-dd"]
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.timeZone = .current

        for format in formatsToTry {
            formatter.dateFormat = format
            if let parsed = formatter.date(from: date) {
                return parsed
            }
        }
        return nil
    }
}

// MARK: - Recognition Errors

enum RecognitionError: LocalizedError {
    case noAPIKey
    case invalidURL
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case parseError
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            "API-ключ не настроен. Проверьте настройки ИИ-ассистента."
        case .invalidURL:
            "Некорректный URL API. Проверьте настройки."
        case .invalidResponse:
            "Некорректный ответ сервера."
        case .apiError(let code, let message):
            "Ошибка API (\(code)): \(message)"
        case .parseError:
            "Не удалось разобрать ответ ИИ."
        case .recognitionFailed(let reason):
            reason
        }
    }
}
