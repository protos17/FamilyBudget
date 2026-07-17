//
//  SettingsViewModel.swift
//  ShareBudget
//
//  Created by Danil on 17.07.2026.
//

import SwiftUI
import Combine

@MainActor
final class SettingsViewModel: ObservableObject {
    let account: Account
    
    @Published var showingCategoryList = false
    @Published var showingResetConfirmation = false
    @Published var exportedFileURL: URL?
    @Published var showingExportError = false
    
    init(account: Account) {
        self.account = account
    }
    
    func exportData(locale: Locale) {
        if let url = CSVExporter.writeToTemporaryFile(for: account, locale: locale) {
            exportedFileURL = url
        } else {
            showingExportError = true
        }
    }
}
