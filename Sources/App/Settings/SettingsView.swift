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

            // MARK: - ИИ-ассистент
            Section {
                Toggle("Включить", isOn: $viewModel.isAIEnabled)

                if viewModel.isAIEnabled {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("API URL")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("https://api.openai.com/v1", text: $viewModel.aiBaseURL)
                            .textContentType(.URL)
                            .autocapitalization(.none)
                            .keyboardType(.URL)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("API ключ")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        SecureField("sk-...", text: $viewModel.aiAPIKey)
                            .textContentType(.password)
                            .autocapitalization(.none)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Модель")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            TextField("gpt-4o", text: $viewModel.aiModel)
                                .autocapitalization(.none)

                            if !viewModel.availableModels.isEmpty {
                                Menu {
                                    ForEach(viewModel.availableModels, id: \.self) { model in
                                        Button {
                                            viewModel.aiModel = model
                                        } label: {
                                            if model == viewModel.aiModel {
                                                Label(model, systemImage: "checkmark")
                                            } else {
                                                Text(model)
                                            }
                                        }
                                    }
                                } label: {
                                    Image(systemName: "chevron.down.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    connectionButton

                    // Постоянный индикатор статуса подключения
                    connectionHealthIndicator
                }
            } header: {
                Text("ИИ-ассистент")
            } footer: {
                Text("Подключите OpenAI-совместимый API для автоматического распознавания трат по фото. Проверьте подключение, чтобы выбрать модель из списка.")
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
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil, from: nil, for: nil
            )
        }
    }

    // MARK: - Connection Button

    @ViewBuilder
    private var connectionButton: some View {
        Button {
            hideKeyboard()
            Task { await viewModel.testAIConnection() }
        } label: {
            HStack(spacing: 8) {
                if viewModel.connectionStatus == .testing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                    Text("Проверяю...")
                } else {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    Text("Проверить подключение")
                }
            }
            .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(.borderedProminent)
        .disabled(viewModel.aiBaseURL.isEmpty
                  || viewModel.aiAPIKey.isEmpty
                  || viewModel.connectionStatus == .testing)
    }

    // MARK: - Persistent Connection Health Indicator

    @ViewBuilder
    private var connectionHealthIndicator: some View {
        HStack(spacing: 8) {
            switch viewModel.connectionStatus {
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("API подключён")
                    .foregroundStyle(.green)

            case .failure(let message):
                Image(systemName: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .lineLimit(2)

            default:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                Text("Подключение не проверено")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .animation(.easeInOut(duration: 0.25), value: viewModel.connectionStatus)
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }
}

// MARK: - Preview

#Preview("Settings") {
    NavigationStack {
        SettingsView()
    }
}

#Preview("Settings — Dark") {
    NavigationStack {
        SettingsView()
            .preferredColorScheme(.dark)
    }
}
