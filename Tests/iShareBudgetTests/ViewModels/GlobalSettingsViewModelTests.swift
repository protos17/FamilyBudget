import Testing
import Foundation
@testable import iShareBudget

@MainActor
@Suite("GlobalSettingsViewModel", .serialized)
struct GlobalSettingsViewModelTests {
    private func makeViewModel(
        store: InMemoryKeyValueStore = InMemoryKeyValueStore(),
        secureStore: InMemorySecureStore = InMemorySecureStore(),
        notifications: MockNotificationScheduler = MockNotificationScheduler(),
        session: URLSession = StubURLProtocol.session()
    ) -> GlobalSettingsViewModel {
        GlobalSettingsViewModel(store: store, secureStore: secureStore, notifications: notifications, session: session)
    }

    // MARK: - Init / defaults

    @Test("defaults when the stores are empty")
    func defaults() {
        let viewModel = makeViewModel()

        #expect(viewModel.remindersEnabled == false)
        #expect(viewModel.isAIEnabled == false)
        #expect(viewModel.aiEngine == .appleIntelligence)
        #expect(viewModel.aiBaseURL == "https://api.openai.com/v1")
        #expect(viewModel.aiModel == "gpt-4o")
        #expect(viewModel.aiAPIKey == "")
        #expect(viewModel.availableModels.isEmpty)

        let components = Calendar.current.dateComponents([.hour, .minute], from: viewModel.reminderTime)
        #expect(components.hour == 20)
        #expect(components.minute == 0)
    }

    @Test("reads pre-existing values from the injected stores")
    func readsSeededValues() {
        let store = InMemoryKeyValueStore(seed: [
            "remindersEnabled": true,
            "isAIEnabled": true,
            "aiEngine": "openAI",
            "aiBaseURL": "https://example.com/v1",
            "aiModel": "custom-model",
            "aiAvailableModels": ["a", "b"]
        ])
        let secureStore = InMemorySecureStore(seed: ["aiAPIKey": "secret-key"])

        let viewModel = makeViewModel(store: store, secureStore: secureStore)

        #expect(viewModel.remindersEnabled == true)
        #expect(viewModel.isAIEnabled == true)
        #expect(viewModel.aiEngine == .openAI)
        #expect(viewModel.aiBaseURL == "https://example.com/v1")
        #expect(viewModel.aiModel == "custom-model")
        #expect(viewModel.aiAPIKey == "secret-key")
        #expect(viewModel.availableModels == ["a", "b"])
    }

    @Test("switching aiEngine persists the new value")
    func switchingAIEnginePersists() {
        let store = InMemoryKeyValueStore()
        let viewModel = makeViewModel(store: store)

        viewModel.aiEngine = .openAI
        #expect(store.string(forKey: "aiEngine") == "openAI")

        viewModel.aiEngine = .appleIntelligence
        #expect(store.string(forKey: "aiEngine") == "appleIntelligence")
    }

    // MARK: - AI toggles

    @Test("disabling AI resets the connection status and persisted validity flag")
    func disablingAIResetsStatus() {
        let store = InMemoryKeyValueStore(seed: ["isAIEnabled": true])
        let viewModel = makeViewModel(store: store)
        viewModel.connectionStatus = .success
        store.set(true, forKey: "isAIConnectionValid")

        viewModel.isAIEnabled = false

        #expect(store.bool(forKey: "isAIConnectionValid") == false)
        #expect(viewModel.connectionStatus == .idle)
    }

    @Test("changing aiBaseURL persists it and clears the cached connection state")
    func changingBaseURLResetsState() {
        let store = InMemoryKeyValueStore()
        let viewModel = makeViewModel(store: store)
        viewModel.availableModels = ["old-model"]
        store.set(true, forKey: "isAIConnectionValid")
        viewModel.connectionStatus = .success

        viewModel.aiBaseURL = "https://example.com/v1"

        #expect(store.string(forKey: "aiBaseURL") == "https://example.com/v1")
        #expect(store.bool(forKey: "isAIConnectionValid") == false)
        #expect(viewModel.connectionStatus == .idle)
        #expect(viewModel.availableModels.isEmpty)
    }

    @Test("setting a non-empty aiAPIKey saves it to the secure store; clearing it deletes it")
    func aiAPIKeyPersistence() {
        let secureStore = InMemorySecureStore()
        let viewModel = makeViewModel(secureStore: secureStore)

        viewModel.aiAPIKey = "new-key"
        #expect(secureStore.load(forKey: "aiAPIKey") == "new-key")

        viewModel.aiAPIKey = ""
        #expect(secureStore.load(forKey: "aiAPIKey") == nil)
    }

    // MARK: - Reminders

    @Test("enabling reminders with granted permission schedules using the reminder time")
    func enableRemindersGranted() async {
        let notifications = MockNotificationScheduler()
        notifications.authorizationResult = true
        let viewModel = makeViewModel(notifications: notifications)

        viewModel.remindersEnabled = true

        await waitUntil { !notifications.scheduledTimes.isEmpty }
        let components = Calendar.current.dateComponents([.hour, .minute], from: viewModel.reminderTime)
        #expect(notifications.scheduledTimes.last?.hour == components.hour)
        #expect(notifications.scheduledTimes.last?.minute == components.minute)
    }

    @Test("enabling reminders without permission reverts the toggle")
    func enableRemindersDenied() async {
        let notifications = MockNotificationScheduler()
        notifications.authorizationResult = false
        let viewModel = makeViewModel(notifications: notifications)

        viewModel.remindersEnabled = true

        await waitUntil { viewModel.showingPermissionDeniedAlert == true }
        #expect(viewModel.remindersEnabled == false)
    }

    @Test("disabling reminders cancels the scheduled notification")
    func disableReminders() {
        let store = InMemoryKeyValueStore(seed: ["remindersEnabled": true])
        let notifications = MockNotificationScheduler()
        let viewModel = makeViewModel(store: store, notifications: notifications)

        viewModel.remindersEnabled = false

        #expect(notifications.cancelCount == 1)
    }

    @Test("changing reminderTime reschedules while reminders are enabled")
    func reminderTimeChangeReschedulesWhenEnabled() {
        let store = InMemoryKeyValueStore(seed: ["remindersEnabled": true])
        let notifications = MockNotificationScheduler()
        let viewModel = makeViewModel(store: store, notifications: notifications)
        let newTime = Calendar.current.date(bySettingHour: 7, minute: 30, second: 0, of: .now)!

        viewModel.reminderTime = newTime

        #expect(notifications.scheduledTimes.last?.hour == 7)
        #expect(notifications.scheduledTimes.last?.minute == 30)
    }

    @Test("changing reminderTime while reminders are disabled only persists, without scheduling")
    func reminderTimeChangeWhenDisabled() {
        let store = InMemoryKeyValueStore()
        let notifications = MockNotificationScheduler()
        let viewModel = makeViewModel(store: store, notifications: notifications)
        #expect(notifications.scheduledTimes.isEmpty)
        let newTime = Calendar.current.date(bySettingHour: 7, minute: 30, second: 0, of: .now)!

        viewModel.reminderTime = newTime

        #expect(notifications.scheduledTimes.isEmpty)
        #expect(store.object(forKey: "reminderTime") as? Date == newTime)
    }

    // MARK: - AI connection test

    @Test("testAIConnection fails fast on a malformed base URL")
    func testConnectionMalformedURL() async {
        let store = InMemoryKeyValueStore()
        let viewModel = makeViewModel(store: store)
        viewModel.aiBaseURL = "http://inva lid url"

        await viewModel.testAIConnection()

        #expect(viewModel.connectionStatus == .failure("Некорректный URL"))
        #expect(store.bool(forKey: "isAIConnectionValid") == false)
    }

    @Test("testAIConnection succeeds on 200 and stores the sorted model list")
    func testConnectionSuccess() async {
        let store = InMemoryKeyValueStore()
        let json = #"{"data":[{"id":"gpt-4o"},{"id":"gpt-3.5"}]}"#.data(using: .utf8)!
        StubURLProtocol.stub = .init(statusCode: 200, data: json)
        let viewModel = makeViewModel(store: store)

        await viewModel.testAIConnection()

        #expect(viewModel.connectionStatus == .success)
        #expect(viewModel.availableModels == ["gpt-3.5", "gpt-4o"])
        #expect(store.bool(forKey: "isAIConnectionValid") == true)
    }

    @Test("testAIConnection surfaces a 401 as an invalid API key failure")
    func testConnection401() async {
        StubURLProtocol.stub = .init(statusCode: 401)
        let viewModel = makeViewModel()

        await viewModel.testAIConnection()

        #expect(viewModel.connectionStatus == .failure("Неверный API-ключ (401)"))
    }

    @Test("testAIConnection surfaces a 403 as an access denied failure")
    func testConnection403() async {
        StubURLProtocol.stub = .init(statusCode: 403)
        let viewModel = makeViewModel()

        await viewModel.testAIConnection()

        #expect(viewModel.connectionStatus == .failure("Доступ запрещён (403)"))
    }

    @Test("testAIConnection surfaces other status codes with the code in the message")
    func testConnectionOtherStatus() async {
        StubURLProtocol.stub = .init(statusCode: 500)
        let viewModel = makeViewModel()

        await viewModel.testAIConnection()

        #expect(viewModel.connectionStatus == .failure("Сервер вернул код 500"))
    }

    @Test("testAIConnection surfaces transport errors as a failure")
    func testConnectionTransportError() async {
        StubURLProtocol.stub = .init(error: URLError(.notConnectedToInternet))
        let viewModel = makeViewModel()

        await viewModel.testAIConnection()

        guard case .failure = viewModel.connectionStatus else {
            Issue.record("expected .failure, got \(viewModel.connectionStatus)")
            return
        }
    }

    // MARK: - Notification-driven invalidation

    @Test("posting connectionInvalidatedNotification resets the status to idle")
    func connectionInvalidatedNotificationResetsStatus() async {
        let viewModel = makeViewModel()
        viewModel.connectionStatus = .success

        // The init's observer Task registers with NotificationCenter asynchronously,
        // so a single post right after construction can race it. Retry until it lands.
        for _ in 0..<20 {
            if viewModel.connectionStatus == .idle { break }
            NotificationCenter.default.post(name: GlobalSettingsViewModel.connectionInvalidatedNotification, object: nil)
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(viewModel.connectionStatus == .idle)
    }

    // MARK: - Bundle info

    @Test("appVersion and buildNumber read from the host bundle")
    func versionInfo() {
        let viewModel = makeViewModel()

        #expect(viewModel.appVersion != "—")
        #expect(viewModel.buildNumber != "—")
    }
}
