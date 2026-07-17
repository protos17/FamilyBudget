//
//  SettingsView.swift
//  FamilyBudget
//
//  Created by Danil on 17.07.2026.
//

import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = GlobalSettingsViewModel()
    @AppStorage("appAppearance") private var appAppearance = "system"
    @AppStorage("appLanguage") private var appLanguageRaw = AppLanguage.system.rawValue
    
    var body: some View {
        Form {
            // MARK: - Внешний вид
            Section {
                Picker("Тема", selection: $appAppearance) {
                    Text("Системная").tag("system")
                    Text("Светлая").tag("light")
                    Text("Тёмная").tag("dark")
                }
                
                Picker("Язык", selection: $appLanguageRaw) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language.rawValue)
                    }
                }
            } header: {
                Text("Внешний вид")
            }
            
            // MARK: - Уведомления
            Section {
                Toggle("Напоминания о бюджете", isOn: $viewModel.remindersEnabled)
                
                if viewModel.remindersEnabled {
                    DatePicker(
                        "Время напоминания",
                        selection: $viewModel.reminderTime,
                        displayedComponents: .hourAndMinute
                    )
                }
            } header: {
                Text("Уведомления")
            } footer: {
                Text("Ежедневное напоминание внести доходы и расходы за день.")
            }
            .alert("Уведомления отключены", isPresented: $viewModel.showingPermissionDeniedAlert) {
                Button("Открыть настройки") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Чтобы получать напоминания, разрешите уведомления в настройках устройства.")
            }
            
            // MARK: - О приложении
            Section {
                HStack {
                    Text("Версия")
                    Spacer()
                    Text("\(viewModel.appVersion) (\(viewModel.buildNumber))")
                        .foregroundStyle(.secondary)
                }
                
                Link(destination: URL(string: "https://disk.yandex.ru/d/T4Uf88WJ8G7lmw")!) {
                    Label("Политика конфиденциальности", systemImage: "hand.raised.fill")
                }
                
                Link(destination: URL(string: "mailto:acerg751@mail.ru")!) {
                    Label("Написать в поддержку", systemImage: "envelope.fill")
                }
            } header: {
                Text("О приложении")
            }
        }
        .navigationTitle("Настройки")
    }
}
