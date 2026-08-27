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
        }
    }

    @Published var aiModel: String = UserDefaults.standard.string(forKey: "aiModel") ?? "gpt-4o" {
        didSet { UserDefaults.standard.set(aiModel, forKey: "aiModel") }
    }

    @Published var connectionStatus: AIConnectionStatus = .idle
    @Published var showingFailureMessage = false

    // Auto-hide status indicator after a delay
    private var statusResetTask: Task<Void, Never>?

    init() {
        if remindersEnabled {
            scheduleReminder()
        }
    }

    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    // MARK: - AI Connection Test

    func testAIConnection() async {
        statusResetTask?.cancel()
        connectionStatus = .testing

        let baseURL = aiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = aiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let url = URL(string: "\(baseURL)/models") else {
            connectionStatus = .failure("Некорректный URL")
            UserDefaults.standard.set(false, forKey: "isAIConnectionValid")
            scheduleStatusReset()
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                connectionStatus = .failure("Некорректный ответ сервера")
                UserDefaults.standard.set(false, forKey: "isAIConnectionValid")
                scheduleStatusReset()
                return
            }

            switch httpResponse.statusCode {
            case 200:
                connectionStatus = .success
                UserDefaults.standard.set(true, forKey: "isAIConnectionValid")
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

        scheduleStatusReset()
    }

    /// Сбрасывает статус в `.idle` через 5 секунд
    private func scheduleStatusReset() {
        statusResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self else { return }
            withAnimation { self.connectionStatus = .idle }
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
