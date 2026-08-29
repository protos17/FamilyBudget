//
//  ReviewPromptScheduler.swift
//  iShareBudget
//
//  Decides when it's appropriate to invoke StoreKit's system rating prompt
//  (`RequestReviewAction`). Apple's guidance: never ask on the first launch,
//  only after a few sessions of real use, and don't re-ask too often — the
//  system itself caps this to ~3 times per 365 days, but self-throttling on
//  top of that keeps those few chances for moments that actually matter, and
//  avoids re-prompting for the same app version.
//

import Foundation

@MainActor
final class ReviewPromptScheduler {
    static let shared = ReviewPromptScheduler()

    private enum Keys {
        static let firstLaunchDate = "reviewPrompt.firstLaunchDate"
        static let launchCount = "reviewPrompt.launchCount"
        static let lastPromptDate = "reviewPrompt.lastPromptDate"
        static let lastPromptedVersion = "reviewPrompt.lastPromptedVersion"
    }

    private let store: any KeyValueStore
    private let minimumLaunchCount: Int
    private let minimumDaysSinceFirstLaunch: Int
    private let minimumDaysBetweenPrompts: Int

    init(
        store: any KeyValueStore = UserDefaults.standard,
        minimumLaunchCount: Int = 3,
        minimumDaysSinceFirstLaunch: Int = 2,
        minimumDaysBetweenPrompts: Int = 90
    ) {
        self.store = store
        self.minimumLaunchCount = minimumLaunchCount
        self.minimumDaysSinceFirstLaunch = minimumDaysSinceFirstLaunch
        self.minimumDaysBetweenPrompts = minimumDaysBetweenPrompts
    }

    /// Call once per cold launch, after onboarding is behind the user —
    /// the very first session should never count towards eligibility.
    func recordLaunch(now: Date = .now) {
        if store.object(forKey: Keys.firstLaunchDate) == nil {
            store.set(now, forKey: Keys.firstLaunchDate)
        }
        let count = (store.object(forKey: Keys.launchCount) as? Int) ?? 0
        store.set(count + 1, forKey: Keys.launchCount)
    }

    func isEligibleForPrompt(currentAppVersion: String, now: Date = .now) -> Bool {
        guard let firstLaunch = store.object(forKey: Keys.firstLaunchDate) as? Date else { return false }
        guard (store.object(forKey: Keys.launchCount) as? Int ?? 0) >= minimumLaunchCount else { return false }
        guard daysBetween(firstLaunch, now) >= minimumDaysSinceFirstLaunch else { return false }
        guard store.string(forKey: Keys.lastPromptedVersion) != currentAppVersion else { return false }

        if let lastPrompt = store.object(forKey: Keys.lastPromptDate) as? Date {
            guard daysBetween(lastPrompt, now) >= minimumDaysBetweenPrompts else { return false }
        }
        return true
    }

    func recordPromptShown(currentAppVersion: String, now: Date = .now) {
        store.set(now, forKey: Keys.lastPromptDate)
        store.set(currentAppVersion, forKey: Keys.lastPromptedVersion)
    }

    private func daysBetween(_ start: Date, _ end: Date) -> Int {
        Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
    }
}
