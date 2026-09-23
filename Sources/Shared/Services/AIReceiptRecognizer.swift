import UIKit
import FoundationModels

// MARK: - Выбор движка распознавания

enum AIRecognitionEngine: String, CaseIterable, Identifiable {
    case appleIntelligence = "appleIntelligence"
    case openAI = "openAI"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleIntelligence:
            return String(localized: "Apple Intelligence")
        case .openAI:
            return String(localized: "OpenAI-совместимый API")
        }
    }

    static var current: AIRecognitionEngine {
        AIRecognitionEngine(rawValue: UserDefaults.standard.string(forKey: "aiEngine") ?? "") ?? .appleIntelligence
    }

    static var isCurrentEngineAvailable: Bool {
        switch current {
        case .appleIntelligence:
            return SystemLanguageModel.default.isAvailable
        case .openAI:
            return UserDefaults.standard.bool(forKey: "isAIConnectionValid")
        }
    }
}

// MARK: - AIReceiptRecognizer

enum AIReceiptRecognizer {

    // MARK: - Prompts

    enum PromptTemplates {
        /// Unified system instructions in English for expense receipt and transaction recognition.
        static func systemInstructions(
            availableCategories: [String],
            currentYear: Int = Calendar.current.component(.year, from: .now)
        ) -> String {
            let categoryList = availableCategories.isEmpty ? "None" : availableCategories.joined(separator: ", ")
            return """
            You are an expert financial assistant specialized in recognizing expense transactions from photos of receipts, invoices, payment screens, or products/services.
            Extract details of a single expense transaction strictly following the schema.

            Available categories: [\(categoryList)]

            Rules:
            - title: Concise description of the purchase or merchant/store name (e.g. "Groceries", "Coffee", "Taxi"). Keep original merchant language if applicable.
            - amount: Positive expense amount in standard currency units (e.g. 350.50, not cents).
            - categoryName: The most suitable category name selected ONLY from the available categories list above, or null if none fit.
            - paymentMethod: One of "card", "cash", "transfer", "other".
            - date: OPTIONAL. Date of the transaction from the receipt in "dd-MM-yyyy" or "dd-MM-yyyy HH:mm" format. Always use the current year \(currentYear) for the year in the date. Even if the receipt indicates a different year, has a 2-digit year, or does not specify a year, the year in the date MUST always be \(currentYear). If the date is missing, blurry, unreadable, or not present on the receipt, leave date as null. A missing date is completely normal and acceptable. NEVER treat a missing date as an error or failure!
            - note: Additional details or null.
            - recognitionError: ONLY populate this field if the image does NOT contain any receipt, bill, or financial transaction at all, or if the amount and title are completely illegible. You MUST NEVER set recognitionError or fail recognition just because the date cannot be found or is unclear.
            """
        }

        /// OpenAI-specific system prompt extending system instructions with strict JSON format schema.
        static func openAISystemPrompt(
            availableCategories: [String],
            currentYear: Int = Calendar.current.component(.year, from: .now)
        ) -> String {
            """
            \(systemInstructions(availableCategories: availableCategories, currentYear: currentYear))

            Return STRICTLY a single valid JSON object without markdown formatting, without ```json wrappers, and without any explanatory text, matching the schema:
            {
              "title": "string",
              "amount": 0.0,
              "categoryName": "string or null",
              "paymentMethod": "card|cash|transfer|other",
              "date": "dd-MM-yyyy or null",
              "note": "string or null"
            }

            CRITICAL INSTRUCTIONS:
            - The "date" field is strictly OPTIONAL. If the date is not found or not clearly visible, return "date": null.
            - When returning a date, ALWAYS use the current year \(currentYear) as the year component (format: dd-MM-\(currentYear) or dd-MM-\(currentYear) HH:mm).
            - Do NOT return an error just because the date is missing.
            - Only return JSON: {"error": "reason description"} if the image contains NO financial transaction or purchase whatsoever.
            """
        }

        /// Shared user prompt for both Apple Intelligence and external OpenAI-compatible models.
        static var userPrompt: String {
            let currentYear = Calendar.current.component(.year, from: .now)
            return "Recognize the expense transaction from this receipt image. Always use the current year (\(currentYear)) for the date."
        }
    }

    // MARK: - Recognition Entry Point

    static func recognize(imageData: Data, expenseCategoryNames: [String]) async throws -> RecognizedTransactionData {
        switch AIRecognitionEngine.current {
        case .appleIntelligence:
            return try await recognizeViaAppleIntelligence(imageData: imageData, expenseCategoryNames: expenseCategoryNames)
        case .openAI:
            return try await recognizeViaOpenAICompatibleAPI(imageData: imageData, expenseCategoryNames: expenseCategoryNames)
        }
    }

    // MARK: - Apple Intelligence (iOS 27 FoundationModels)

    private static func recognizeViaAppleIntelligence(
        imageData: Data,
        expenseCategoryNames: [String]
    ) async throws -> RecognizedTransactionData {
        let systemModel = SystemLanguageModel.default
        guard systemModel.isAvailable else {
            throw RecognitionError.appleIntelligenceUnavailable
        }

        guard let image = UIImage(data: imageData) else {
            throw RecognitionError.invalidResponse
        }

        let instructions = PromptTemplates.systemInstructions(availableCategories: expenseCategoryNames)
        let session = LanguageModelSession(model: systemModel, instructions: instructions)

        do {
            let response = try await session.respond(generating: RecognizedTransactionData.self) {
                PromptTemplates.userPrompt
                Attachment(image)
            }

            let content = response.content
            if let errorMessage = content.recognitionError, !errorMessage.isEmpty {
                // Если название и сумма успешно распознаны, или ошибка касается только даты —
                // не прерываем распознавание, дата полностью опциональна.
                let hasValidTransaction = content.amount > 0 && !content.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let isDateError = errorMessage.localizedCaseInsensitiveContains("date") ||
                                  errorMessage.localizedCaseInsensitiveContains("дат")

                if !hasValidTransaction && !isDateError {
                    throw RecognitionError.recognitionFailed(errorMessage)
                }
            }
            return content
        } catch let error as RecognitionError {
            throw error
        } catch SystemLanguageModel.Error.assetsUnavailable {
            throw RecognitionError.appleIntelligenceUnavailable
        } catch {
            #if DEBUG
            print("AIReceiptRecognizer Apple Intelligence error: \(error)")
            #endif
            throw RecognitionError.apiError(statusCode: -1, message: error.localizedDescription)
        }
    }

    // MARK: - OpenAI-совместимый эндпоинт (HTTP)

    private static func recognizeViaOpenAICompatibleAPI(
        imageData: Data,
        expenseCategoryNames: [String]
    ) async throws -> RecognizedTransactionData {
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

        let systemPrompt = PromptTemplates.openAISystemPrompt(availableCategories: expenseCategoryNames)

        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": PromptTemplates.userPrompt],
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

        guard let contentData = extractJSONData(from: content) else {
            throw RecognitionError.parseError
        }

        if let parsed = try? JSONSerialization.jsonObject(with: contentData) as? [String: Any],
           let errorMessage = parsed["error"] as? String {
            let title = parsed["title"] as? String ?? ""
            let amount = (parsed["amount"] as? NSNumber)?.doubleValue ?? 0
            let hasValidTransaction = amount > 0 && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let isDateError = errorMessage.localizedCaseInsensitiveContains("date") ||
                              errorMessage.localizedCaseInsensitiveContains("дат")

            if !hasValidTransaction && !isDateError {
                throw RecognitionError.recognitionFailed(errorMessage)
            }
        }

        do {
            return try JSONDecoder().decode(RecognizedTransactionData.self, from: contentData)
        } catch {
            throw RecognitionError.parseError
        }
    }

    // MARK: - Вспомогательные методы

    /// Извлекает валидный JSON-объект из текста, даже если модель добавила markdown или пояснения.
    private static func extractJSONData(from content: String) -> Data? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        if let data = trimmed.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            return data
        }

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

@Generable
struct RecognizedTransactionData: Codable {
    @Guide(description: "Short description of the expense or merchant name, e.g. \"Coffee\", \"Groceries\", \"Taxi\"")
    let title: String

    @Guide(description: "Expense amount as a positive number in standard currency units (e.g. 350.50, not cents)")
    let amount: Double

    @Guide(description: "Name of the most suitable category ONLY from the available categories list in the instructions, or null if none fit")
    let categoryName: String?

    @Guide(description: "Payment method", .anyOf(["card", "cash", "transfer", "other"]))
    let paymentMethod: String?

    @Guide(description: "OPTIONAL date from the receipt in dd-MM-yyyy (or dd-MM-yyyy HH:mm). Always use the current year for the year component. Return null if the date is missing, unreadable, or not clearly visible. A missing date is completely normal and NOT an error.")
    let date: String?

    @Guide(description: "Additional details about the transaction or null")
    let note: String?

    @Guide(description: "Only set this if the image is NOT a receipt or financial transaction at all. Must be null if amount and title are recognized, even when date is absent.")
    let recognitionError: String?

    init(
        title: String,
        amount: Double,
        categoryName: String? = nil,
        paymentMethod: String? = nil,
        date: String? = nil,
        note: String? = nil,
        recognitionError: String? = nil
    ) {
        self.title = title
        self.amount = amount
        self.categoryName = categoryName
        self.paymentMethod = paymentMethod
        self.date = date
        self.note = note
        self.recognitionError = recognitionError
    }

    /// Парсит `date` в `Date`, пробуя несколько форматов, приводя год к текущему и отсекая некорректные даты.
    var parsedDate: Date? {
        guard let date, !date.isEmpty else { return nil }

        let trimmed = date.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !["null", "nil", "none", "unknown", "n/a", "не указана", "не найдена", "отсутствует"].contains(trimmed.lowercased()) else {
            return nil
        }

        let formatsToTry = [
            "dd-MM-yyyy",
            "dd-MM-yyyy HH:mm",
            "dd.MM.yyyy",
            "dd.MM.yyyy HH:mm",
            "yyyy-MM-dd",
            "yyyy-MM-dd HH:mm:ss",
            "dd/MM/yyyy",
            "dd/MM/yyyy HH:mm",
            "dd-MM-yy",
            "dd-MM-yy HH:mm",
            "dd.MM.yy",
            "dd.MM.yy HH:mm",
            "dd/MM/yy",
            "dd/MM/yy HH:mm",
            "dd-MM",
            "dd.MM",
            "dd/MM"
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current

        let currentYear = Calendar.current.component(.year, from: .now)

        for format in formatsToTry {
            formatter.dateFormat = format
            if let parsed = formatter.date(from: trimmed) {
                var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: parsed)
                components.year = currentYear
                return Calendar.current.date(from: components) ?? parsed
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
    case appleIntelligenceUnavailable

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return String(localized: "API-ключ не настроен. Проверьте настройки ИИ-ассистента.")
        case .invalidURL:
            return String(localized: "Некорректный URL API. Проверьте настройки.")
        case .invalidResponse:
            return String(localized: "Некорректный ответ сервера.")
        case .apiError(let code, let message):
            return String(localized: "Ошибка API (\(code)): \(message)")
        case .parseError:
            return String(localized: "Не удалось разобрать ответ ИИ.")
        case .recognitionFailed(let reason):
            return reason
        case .appleIntelligenceUnavailable:
            return String(localized: "Apple Intelligence недоступен на этом устройстве. Проверьте настройки системы или выберите внешнего провайдера.")
        }
    }
}
