//
//  NotificationManager.swift
//  FamilyBudget
//
//  Created by Danil on 17.07.2026.
//

import Foundation
import UserNotifications

@MainActor
final class NotificationManager {
    static let shared = NotificationManager()
    
    private let dailyReminderIdentifier = "daily-budget-reminder"
    
    private init() {}
    
    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }
    
    func checkAuthorizationStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }
    
    func scheduleDailyReminder(at time: DateComponents) {
        let center = UNUserNotificationCenter.current()
        
        center.removePendingNotificationRequests(withIdentifiers: [dailyReminderIdentifier])
        
        let content = UNMutableNotificationContent()
        content.title = "Семейный бюджет"
        content.body = "Не забудьте внести доходы и расходы за сегодня."
        content.sound = .default
        
        var trigger = time
        trigger.calendar = Calendar.current
        
        let dateTrigger = UNCalendarNotificationTrigger(dateMatching: trigger, repeats: true)
        let request = UNNotificationRequest(
            identifier: dailyReminderIdentifier,
            content: content,
            trigger: dateTrigger
        )
        
        center.add(request)
    }
    
    func cancelDailyReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [dailyReminderIdentifier])
    }
}
