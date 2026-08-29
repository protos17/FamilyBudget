//
//  OnboardingViewModel.swift
//  iShareBudget
//
//  Shown once to new users, see RootTabView + SettingsView (reset entry point).
//

import SwiftUI

struct OnboardingPage: Identifiable, Sendable {
    let id: Int
    let systemImage: String
    let colorHex: String
    let title: String
    let message: String

    static let all: [OnboardingPage] = [
        OnboardingPage(
            id: 0,
            systemImage: "creditcard.fill",
            colorHex: "54A0FF",
            title: "Бюджеты под контролем",
            message: "Ведите доходы и расходы по месяцам. У каждого бюджета своя валюта и свой лимит."
        ),
        OnboardingPage(
            id: 1,
            systemImage: "person.2.fill",
            colorHex: "1DD1A1",
            title: "Общий доступ через iCloud",
            message: "Пригласите семью в бюджет — операции синхронизируются на всех устройствах."
        ),
        OnboardingPage(
            id: 2,
            systemImage: "chart.pie.fill",
            colorHex: "FF9F43",
            title: "Категории и аналитика",
            message: "Диаграммы по категориям, лимиты расходов и экспорт операций в CSV."
        ),
        OnboardingPage(
            id: 3,
            systemImage: "doc.text.viewfinder",
            colorHex: "6C5CE7",
            title: "Чек превращается в операции",
            message: "Подключите свой ИИ-сервис в настройках и просто сфотографируйте чек."
        )
    ]
}

@MainActor
final class OnboardingViewModel: ObservableObject {
    static let storageKey = "hasCompletedOnboarding"

    @Published var currentPage = 0

    let pages = OnboardingPage.all

    private let store: any KeyValueStore

    init(store: any KeyValueStore = UserDefaults.standard) {
        self.store = store
    }

    var isLastPage: Bool {
        currentPage >= pages.count - 1
    }

    func advance() {
        if isLastPage {
            finish()
        } else {
            currentPage += 1
        }
    }

    func skip() {
        finish()
    }

    func finish() {
        store.set(true, forKey: Self.storageKey)
    }
}
