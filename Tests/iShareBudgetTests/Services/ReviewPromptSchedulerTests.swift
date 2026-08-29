import Testing
import Foundation
@testable import iShareBudget

@MainActor
@Suite("ReviewPromptScheduler")
struct ReviewPromptSchedulerTests {
    private func days(_ count: Int, after date: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: count, to: date) ?? date
    }

    @Test("not eligible before the first launch is ever recorded")
    func notEligibleWithoutAnyLaunch() {
        let scheduler = ReviewPromptScheduler(store: InMemoryKeyValueStore())

        #expect(scheduler.isEligibleForPrompt(currentAppVersion: "1.0") == false)
    }

    @Test("not eligible below the minimum launch count")
    func notEligibleBelowLaunchThreshold() {
        let scheduler = ReviewPromptScheduler(
            store: InMemoryKeyValueStore(), minimumLaunchCount: 3, minimumDaysSinceFirstLaunch: 0
        )
        let now = Date.now
        scheduler.recordLaunch(now: now)
        scheduler.recordLaunch(now: now)

        #expect(scheduler.isEligibleForPrompt(currentAppVersion: "1.0", now: now) == false)
    }

    @Test("not eligible until enough days have passed since the first launch")
    func notEligibleBeforeMinimumDaysSinceFirstLaunch() {
        let scheduler = ReviewPromptScheduler(
            store: InMemoryKeyValueStore(), minimumLaunchCount: 1, minimumDaysSinceFirstLaunch: 2
        )
        let firstLaunch = Date.now
        scheduler.recordLaunch(now: firstLaunch)

        #expect(scheduler.isEligibleForPrompt(currentAppVersion: "1.0", now: days(1, after: firstLaunch)) == false)
        #expect(scheduler.isEligibleForPrompt(currentAppVersion: "1.0", now: days(2, after: firstLaunch)) == true)
    }

    @Test("eligible once launch count and elapsed-days thresholds are both met")
    func eligibleOnceThresholdsAreMet() {
        let scheduler = ReviewPromptScheduler(
            store: InMemoryKeyValueStore(), minimumLaunchCount: 3, minimumDaysSinceFirstLaunch: 2
        )
        let firstLaunch = Date.now
        scheduler.recordLaunch(now: firstLaunch)
        scheduler.recordLaunch(now: days(1, after: firstLaunch))
        scheduler.recordLaunch(now: days(3, after: firstLaunch))

        #expect(scheduler.isEligibleForPrompt(currentAppVersion: "1.0", now: days(3, after: firstLaunch)) == true)
    }

    @Test("recordPromptShown blocks an immediate re-prompt, even for a new app version")
    func recordPromptShownBlocksImmediateRepeat() {
        let scheduler = ReviewPromptScheduler(
            store: InMemoryKeyValueStore(),
            minimumLaunchCount: 1, minimumDaysSinceFirstLaunch: 0, minimumDaysBetweenPrompts: 90
        )
        let now = Date.now
        scheduler.recordLaunch(now: now)
        #expect(scheduler.isEligibleForPrompt(currentAppVersion: "1.0", now: now) == true)

        scheduler.recordPromptShown(currentAppVersion: "1.0", now: now)

        #expect(scheduler.isEligibleForPrompt(currentAppVersion: "1.0", now: now) == false)
        #expect(scheduler.isEligibleForPrompt(currentAppVersion: "1.1", now: now) == false)
    }

    @Test("a repeat prompt becomes eligible again only after the cooldown window passes")
    func repeatPromptEligibleAfterCooldown() {
        let scheduler = ReviewPromptScheduler(
            store: InMemoryKeyValueStore(),
            minimumLaunchCount: 1, minimumDaysSinceFirstLaunch: 0, minimumDaysBetweenPrompts: 90
        )
        let firstLaunch = Date.now
        scheduler.recordLaunch(now: firstLaunch)
        scheduler.recordPromptShown(currentAppVersion: "1.0", now: firstLaunch)

        #expect(scheduler.isEligibleForPrompt(currentAppVersion: "1.1", now: days(89, after: firstLaunch)) == false)
        #expect(scheduler.isEligibleForPrompt(currentAppVersion: "1.1", now: days(91, after: firstLaunch)) == true)
    }

    @Test("a repeat prompt for the same version stays blocked even after the cooldown window passes")
    func sameVersionStaysBlockedAfterCooldown() {
        let scheduler = ReviewPromptScheduler(
            store: InMemoryKeyValueStore(),
            minimumLaunchCount: 1, minimumDaysSinceFirstLaunch: 0, minimumDaysBetweenPrompts: 90
        )
        let firstLaunch = Date.now
        scheduler.recordLaunch(now: firstLaunch)
        scheduler.recordPromptShown(currentAppVersion: "1.0", now: firstLaunch)

        #expect(scheduler.isEligibleForPrompt(currentAppVersion: "1.0", now: days(91, after: firstLaunch)) == false)
    }

    @Test("recordLaunch sets the first-launch date only once and keeps incrementing the count")
    func recordLaunchSetsFirstLaunchDateOnce() {
        let store = InMemoryKeyValueStore()
        let scheduler = ReviewPromptScheduler(store: store)
        let firstLaunch = Date.now

        scheduler.recordLaunch(now: firstLaunch)
        scheduler.recordLaunch(now: days(5, after: firstLaunch))

        #expect(store.object(forKey: "reviewPrompt.firstLaunchDate") as? Date == firstLaunch)
        #expect(store.object(forKey: "reviewPrompt.launchCount") as? Int == 2)
    }
}
