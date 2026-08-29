import Foundation
@testable import iShareBudget

@MainActor
final class MockNotificationScheduler: NotificationScheduling {
    var authorizationResult = true
    private(set) var scheduledTimes: [DateComponents] = []
    private(set) var cancelCount = 0

    func requestAuthorization() async -> Bool {
        authorizationResult
    }

    func scheduleDailyReminder(at time: DateComponents) {
        scheduledTimes.append(time)
    }

    func cancelDailyReminder() {
        cancelCount += 1
    }
}
