//
//  RootTabView.swift
//  FamilyBudget
//
//  Created by Danil on 17.07.2026.
//

import SwiftUI
import StoreKit

struct RootTabView: View {
    @AppStorage(OnboardingViewModel.storageKey) private var hasCompletedOnboarding = false
    @Environment(\.requestReview) private var requestReview

    var body: some View {
        TabView {
            NavigationStack {
                ListsView()
            }
            .tabItem {
                Label("Бюджеты", systemImage: "creditcard.fill")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Настройки", systemImage: "gearshape.fill")
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { !hasCompletedOnboarding },
            set: { hasCompletedOnboarding = !$0 }
        )) {
            OnboardingView()
        }
        .task(id: hasCompletedOnboarding) {
            await promptForReviewIfEligible()
        }
    }

    /// Never asks during the very first session (onboarding); after that, only once
    /// the user has opened the app a few times and a couple of days have passed.
    /// The short delay avoids interrupting the app's own launch.
    private func promptForReviewIfEligible() async {
        guard hasCompletedOnboarding else { return }

        let scheduler = ReviewPromptScheduler.shared
        scheduler.recordLaunch()

        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        guard scheduler.isEligibleForPrompt(currentAppVersion: currentVersion) else { return }

        try? await Task.sleep(for: .seconds(2))
        requestReview()
        scheduler.recordPromptShown(currentAppVersion: currentVersion)
    }
}
