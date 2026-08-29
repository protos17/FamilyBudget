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
    @Published var remindersEnabled: Bool {
        didSet { handleRemindersToggle() }
    }

    @Published var reminderTime: Date {
        didSet {
            store.set(reminderTime, forKey: "reminderTime")
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

    @Published var isAIEnabled: Bool {
        didSet {
            store.set(isAIEnabled, forKey: "isAIEnabled")
            // Сбрасываем статус подключения при выключении
            if !isAIEnabled {
                store.set(false, forKey: "isAIConnectionValid")
                connectionStatus = .idle
            }
        }
    }

    @Published var aiBaseURL: String {
        didSet {
            store.set(aiBaseURL, forKey: "aiBaseURL")
            // Сбрасываем статус при изменении URL
            store.set(false, forKey: "isAIConnectionValid")
            connectionStatus = .idle
            availableModels = []
        }
    }

    @Published var aiAPIKey: String {
        didSet {
            if aiAPIKey.isEmpty {
                secureStore.delete(forKey: Self.aiAPIKeychainKey)
            } else {
                secureStore.save(aiAPIKey, forKey: Self.aiAPIKeychainKey)
            }
            // Сбрасываем статус при изменении ключа
            store.set(false, forKey: "isAIConnectionValid")
            connectionStatus = .idle
            availableModels = []
        }
    }

    @Published var aiModel: String {
        didSet { store.set(aiModel, forKey: "aiModel") }
    }

    /// Список моделей, полученный от API при проверке подключения — используется для пикера в настройках
    @Published var availableModels: [String] {
        didSet { store.set(availableModels, forKey: "aiAvailableModels") }
    }

    @Published var connectionStatus: AIConnectionStatus = .idle
    @Published var showingFailureMessage = false

    private var connectionInvalidationTask: Task<Void, Never>?
    private let store: any KeyValueStore
    private let secureStore: any SecureStore
    private let notifications: any NotificationScheduling
    private let session: URLSession

    init(
        store: any KeyValueStore = UserDefaults.standard,
        secureStore: any SecureStore = KeychainSecureStore(),
        notifications: any NotificationScheduling = NotificationManager.shared,
        session: URLSession = .shared
    ) {
        self.store = store
        self.secureStore = secureStore
        self.notifications = notifications
        self.session = session

        self.remindersEnabled = store.bool(forKey: "remindersEnabled")
        self.reminderTime = (store.object(forKey: "reminderTime") as? Date)
            ?? Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: .now) ?? .now
        self.isAIEnabled = store.bool(forKey: "isAIEnabled")
        self.aiBaseURL = store.string(forKey: "aiBaseURL") ?? "https://api.openai.com/v1"
        self.aiAPIKey = secureStore.load(forKey: Self.aiAPIKeychainKey) ?? ""
        self.aiModel = store.string(forKey: "aiModel") ?? "gpt-4o"
        self.availableModels = store.stringArray(forKey: "aiAvailableModels") ?? []

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
            store.set(false, forKey: "isAIConnectionValid")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                connectionStatus = .failure("Некорректный ответ сервера")
                store.set(false, forKey: "isAIConnectionValid")
                return
            }

            switch httpResponse.statusCode {
            case 200:
                connectionStatus = .success
                store.set(true, forKey: "isAIConnectionValid")

                if let decoded = try? JSONDecoder().decode(ModelsListResponse.self, from: data) {
                    let ids = decoded.data.map(\.id).sorted()
                    if !ids.isEmpty {
                        availableModels = ids
                    }
                }
            case 401:
                connectionStatus = .failure("Неверный API-ключ (401)")
                store.set(false, forKey: "isAIConnectionValid")
            case 403:
                connectionStatus = .failure("Доступ запрещён (403)")
                store.set(false, forKey: "isAIConnectionValid")
            default:
                connectionStatus = .failure("Сервер вернул код \(httpResponse.statusCode)")
                store.set(false, forKey: "isAIConnectionValid")
            }
        } catch {
            connectionStatus = .failure(error.localizedDescription)
            store.set(false, forKey: "isAIConnectionValid")
        }
    }

    // MARK: - Reminders

    private func handleRemindersToggle() {
        store.set(remindersEnabled, forKey: "remindersEnabled")

        if remindersEnabled {
            Task {
                let granted = await notifications.requestAuthorization()
                if granted {
                    scheduleReminder()
                } else {
                    remindersEnabled = false
                    showingPermissionDeniedAlert = true
                }
            }
        } else {
            notifications.cancelDailyReminder()
        }
    }

    private func scheduleReminder() {
        let components = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        notifications.scheduleDailyReminder(at: components)
    }
}
