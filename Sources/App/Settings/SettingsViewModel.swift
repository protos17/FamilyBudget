//
//  SettingsViewModel.swift
//  FamilyBudget
//
//  Created by Danil on 17.07.2026.
//

import SwiftUI
import Combine

@MainActor
final class SettingsViewModel: ObservableObject {
    let account: Account

    @Published var showingCategoryList = false
    @Published var showingResetConfirmation = false
    @Published var showingLeaveConfirmation = false
    @Published var remindersEnabled: Bool = UserDefaults.standard.bool(forKey: "remindersEnabled") {
        didSet { handleRemindersToggle() }
    }

    @Published var reminderTime: Date = {
        if let saved = UserDefaults.standard.object(forKey: "reminderTime") as? Date {
            return saved
        }
        // По умолчанию 20:00
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
    @Published var exportedFileURL: URL?
    @Published var showingExportError = false

    init(account: Account) {
        self.account = account
    }

    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var sharingStatusText: String {
        guard account.isShared else { return "Не расшарен" }
        return UserIdentityService.shared.isCurrentUserOwner(of: account)
            ? "Вы владелец"
            : "Общий доступ"
    }
    
    func exportData() {
        if let url = CSVExporter.writeToTemporaryFile(for: account) {
            exportedFileURL = url
        } else {
            showingExportError = true
        }
    }

    private func handleRemindersToggle() {
        UserDefaults.standard.set(remindersEnabled, forKey: "remindersEnabled")

        if remindersEnabled {
            Task {
                let granted = await NotificationManager.shared.requestAuthorization()
                if granted {
                    scheduleReminder()
                } else {
                    // Пользователь отказал в разрешении — откатываем тоггл и показываем алерт
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
