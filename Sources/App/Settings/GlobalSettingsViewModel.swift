//
//  SettingsViewModel.swift
//  FamilyBudget
//
//  Created by Danil on 17.07.2026.
//

import SwiftUI
import Combine

@MainActor
final class GlobalSettingsViewModel: ObservableObject {
    @Published var remindersEnabled: Bool = UserDefaults.standard.bool(forKey: "remindersEnabled") {
        didSet { handleRemindersToggle() }
    }

    @Published var reminderTime: Date = {
        if let saved = UserDefaults.standard.object(forKey: "reminderTime") as? Date {
            return saved
        }
        return Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: .now) ?? .now
    }() {
        didSet {
            UserDefaults.standard.set(reminderTime, forKey: "reminderTime")
            if remindersEnabled {
                scheduleReminder()
            }
        }
    }

    @Published var showingPermissionDeniedAlert = false

    // MARK: - AI / OpenAI-compatible API

    private static let aiAPIKeychainKey = "aiAPIKey"

    enum AIConnectionStatus: Equatable {
        case idle
        case testing
        case success
        case failure(String)
    }

    private struct ModelsListResponse: Decodable {
        struct ModelEntry: Decodable { let id: String }
        let data: [ModelEntry]
    }

    /// Отправляется из мест, где используется ИИ-распознавание, при ошибке запроса к API
    static let connectionInvalidatedNotification = Notification.Name("aiConnectionInvalidated")

    @Published var isAIEnabled: Bool = UserDefaults.standard.bool(forKey: "isAIEnabled") {
        didSet {
            UserDefaults.standard.set(isAIEnabled, forKey: "isAIEnabled")
            // Сбрасываем статус подключения при выключении
            if !isAIEnabled {
                UserDefaults.standard.set(false, forKey: "isAIConnectionValid")
                connectionStatus = .idle
            }
        }
    }

    @Published var aiBaseURL: String = UserDefaults.standard.string(forKey: "aiBaseURL") ?? "https://api.openai.com/v1" {
        didSet {
            UserDefaults.standard.set(aiBaseURL, forKey: "aiBaseURL")
            // Сбрасываем статус при изменении URL
            UserDefaults.standard.set(false, forKey: "isAIConnectionValid")
            connectionStatus = .idle
            availableModels = []
        }
    }

    @Published var aiAPIKey: String = KeychainHelper.load(forKey: aiAPIKeychainKey) ?? "" {
        didSet {
            if aiAPIKey.isEmpty {
                KeychainHelper.delete(forKey: Self.aiAPIKeychainKey)
            } else {
                KeychainHelper.save(aiAPIKey, forKey: Self.aiAPIKeychainKey)
            }
            // Сбрасываем статус при изменении ключа
            UserDefaults.standard.set(false, forKey: "isAIConnectionValid")
            connectionStatus = .idle
            availableModels = []
        }
    }

    @Published var aiModel: String = UserDefaults.standard.string(forKey: "aiModel") ?? "gpt-4o" {
        didSet { UserDefaults.standard.set(aiModel, forKey: "aiModel") }
    }

    /// Список моделей, полученный от API при проверке подключения — используется для пикера в настройках
    @Published var availableModels: [String] = UserDefaults.standard.stringArray(forKey: "aiAvailableModels") ?? [] {
        didSet { UserDefaults.standard.set(availableModels, forKey: "aiAvailableModels") }
    }

    @Published var connectionStatus: AIConnectionStatus = .idle
    @Published var showingFailureMessage = false

    private var connectionInvalidationTask: Task<Void, Never>?

    init() {
        if remindersEnabled {
            scheduleReminder()
        }

        connectionInvalidationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await _ in NotificationCenter.default.notifications(named: Self.connectionInvalidatedNotification) {
                self.connectionStatus = .idle
            }
        }
    }

    deinit {
        connectionInvalidationTask?.cancel()
    }

    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    // MARK: - AI Connection Test

    func testAIConnection() async {
        connectionStatus = .testing

        let baseURL = aiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = aiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let url = URL(string: "\(baseURL)/models") else {
            connectionStatus = .failure("Некорректный URL")
            UserDefaults.standard.set(false, forKey: "isAIConnectionValid")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                connectionStatus = .failure("Некорректный ответ сервера")
                UserDefaults.standard.set(false, forKey: "isAIConnectionValid")
                return
            }

            switch httpResponse.statusCode {
            case 200:
                connectionStatus = .success
                UserDefaults.standard.set(true, forKey: "isAIConnectionValid")

                if let decoded = try? JSONDecoder().decode(ModelsListResponse.self, from: data) {
                    let ids = decoded.data.map(\.id).sorted()
                    if !ids.isEmpty {
                        availableModels = ids
                    }
                }
            case 401:
                connectionStatus = .failure("Неверный API-ключ (401)")
                UserDefaults.standard.set(false, forKey: "isAIConnectionValid")
            case 403:
                connectionStatus = .failure("Доступ запрещён (403)")
                UserDefaults.standard.set(false, forKey: "isAIConnectionValid")
            default:
                connectionStatus = .failure("Сервер вернул код \(httpResponse.statusCode)")
                UserDefaults.standard.set(false, forKey: "isAIConnectionValid")
            }
        } catch {
            connectionStatus = .failure(error.localizedDescription)
            UserDefaults.standard.set(false, forKey: "isAIConnectionValid")
        }
    }

    // MARK: - Reminders

    private func handleRemindersToggle() {
        UserDefaults.standard.set(remindersEnabled, forKey: "remindersEnabled")

        if remindersEnabled {
            Task {
                let granted = await NotificationManager.shared.requestAuthorization()
                if granted {
                    scheduleReminder()
                } else {
                    remindersEnabled = false
                    showingPermissionDeniedAlert = true
                }
            }
        } else {
            NotificationManager.shared.cancelDailyReminder()
        }
    }

    private func scheduleReminder() {
        let components = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        NotificationManager.shared.scheduleDailyReminder(at: components)
    }
}
