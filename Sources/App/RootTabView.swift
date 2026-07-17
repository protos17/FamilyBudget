//
//  RootTabView.swift
//  FamilyBudget
//
//  Created by Danil on 17.07.2026.
//

import SwiftUI

struct RootTabView: View {
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
    }
}
