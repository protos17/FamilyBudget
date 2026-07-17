//
//  RootTabView.swift
//  FamilyBudget
//
//  Created by Danil on 17.07.2026.
//

import SwiftUI

struct RootTabView: View {
    let account: Account

    var body: some View {
        TabView {
            NavigationStack {
                ListDetailView(list: account)
            }
            .tabItem {
                Label("Бюджет", systemImage: "creditcard.fill")
            }

            NavigationStack {
                SettingsView(account: account)
            }
            .tabItem {
                Label("Настройки", systemImage: "gearshape.fill")
            }
        }
    }
}
