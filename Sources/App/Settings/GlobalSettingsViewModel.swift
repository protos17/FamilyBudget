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
