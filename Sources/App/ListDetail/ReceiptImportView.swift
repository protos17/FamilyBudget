//
//  ReceiptImportView.swift
//  FamilyBudget
//
//  Invisible overlay that picks up a receipt photo handed off by
//  ReceiptShareExtension (see ReceiptImportCoordinator in
//  FamilyBudgetApp.swift), asks which budget it belongs to, recognizes it
//  with the same AI service used by the in-app "Распознать по фото" flow,
//  and saves the resulting transaction.
//

import SwiftUI
import SwiftData

struct ReceiptImportView: View {
    @ObservedObject private var coordinator = ReceiptImportCoordinator.shared
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    @State private var selectedAccount: Account?
    @State private var showingAccountPicker = false
    @State private var showingNoAccountsAlert = false
    @State private var isRecognizing = false
    @State private var recognizedResult: RecognizedTransactionData?
    @State private var showingRecognitionResult = false
    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: coordinator.pendingImageData) { _, data in
                guard data != nil else { return }
                startImport()
            }
            .overlay {
                if isRecognizing {
                    ZStack {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                        VStack(spacing: 16) {
                            ProgressView()
                                .controlSize(.large)
                                .tint(.white)
                            Text("Распознаю…")
                                .font(.headline)
                                .foregroundStyle(.white)
                        }
                        .padding(32)
                        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isRecognizing)
            .confirmationDialog(
                "В какой бюджет добавить операцию?",
                isPresented: $showingAccountPicker,
                titleVisibility: .visible
            ) {
                ForEach(accounts) { account in
                    Button(account.name) {
                        selectedAccount = account
                        recognize(for: account)
                    }
                }
                Button("Отмена", role: .cancel) {
                    coordinator.clearPendingImage()
                }
            }
            .alert("Нет бюджетов", isPresented: $showingNoAccountsAlert) {
                Button("OK", role: .cancel) { coordinator.clearPendingImage() }
            } message: {
                Text("Создайте бюджет в приложении, чтобы распознавать чеки.")
            }
            .alert("Ошибка", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .confirmationDialog(
                "Распознано",
                isPresented: $showingRecognitionResult,
                titleVisibility: .visible
            ) {
                Button("Сохранить") {
                    if let result = recognizedResult, let account = selectedAccount {
                        saveRecognizedTransaction(result, into: account)
                    }
                    recognizedResult = nil
                    coordinator.clearPendingImage()
                }
                Button("Отмена", role: .cancel) {
                    recognizedResult = nil
                    coordinator.clearPendingImage()
                }
            } message: {
                if let result = recognizedResult, let account = selectedAccount {
                    let categoryName = result.categoryName ?? "без категории"
                    let amount = Decimal(result.amount).formattedAsCurrency(code: account.currencyCode)
                    Text("\(result.title) · \(amount) · \(categoryName)")
                }
            }
    }

    // MARK: - Import Flow

    private func startImport() {
        guard UserDefaults.standard.bool(forKey: "isAIEnabled") else {
            errorMessage = "Включите ИИ-ассистента в настройках, чтобы распознавать чеки."
            showingError = true
            coordinator.clearPendingImage()
            return
        }

        if accounts.isEmpty {
            showingNoAccountsAlert = true
            return
        }
        if accounts.count == 1, let only = accounts.first {
            selectedAccount = only
            recognize(for: only)
            return
        }
        showingAccountPicker = true
    }

    private func recognize(for account: Account) {
        guard let data = coordinator.pendingImageData else { return }
        let expenseCategories = account.sortedCategories.filter {
            $0.kind == .expense || $0.kind == .universal
        }

        isRecognizing = true
        Task {
            defer { isRecognizing = false }
            do {
                let result = try await AIReceiptRecognizer.recognize(
                    imageData: data,
                    expenseCategoryNames: expenseCategories.map(\.name)
                )
                recognizedResult = result
                showingRecognitionResult = true
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
                coordinator.clearPendingImage()

                UserDefaults.standard.set(false, forKey: "isAIConnectionValid")
                NotificationCenter.default.post(name: GlobalSettingsViewModel.connectionInvalidatedNotification, object: nil)
            }
        }
    }

    private func saveRecognizedTransaction(_ result: RecognizedTransactionData, into account: Account) {
        let amountMinorUnits = Int((result.amount * 100).rounded())

        let transaction = Transaction(
            title: result.title,
            amountMinorUnits: amountMinorUnits,
            type: .expense,
            date: .now,
            createdByUserID: UserIdentityService.shared.currentUserID
        )

        if let categoryName = result.categoryName {
            transaction.category = account.sortedCategories.first {
                $0.name.localizedCaseInsensitiveCompare(categoryName) == .orderedSame
            }
        }

        if let pm = result.paymentMethod {
            transaction.paymentMethod = PaymentMethod(rawValue: pm) ?? .other
        }

        transaction.note = result.note
        transaction.account = account

        modelContext.insert(transaction)
        try? modelContext.save()

        if account.isShared {
            Task {
                try? await SharingManager.shared.pushItem(transaction, for: account)
            }
        }
    }
}
