import Testing
import Foundation
@testable import iShareBudget

@MainActor
@Suite("SettingsViewModel")
final class SettingsViewModelTests {
    private var createdFiles: [URL] = []

    deinit {
        for url in createdFiles {
            try? FileManager.default.removeItem(at: url)
        }
    }

    @Test("initial state has no export in flight")
    func initialState() {
        let viewModel = SettingsViewModel(account: MockData.makeAccount())

        #expect(viewModel.showingCategoryList == false)
        #expect(viewModel.showingResetConfirmation == false)
        #expect(viewModel.exportedFileURL == nil)
        #expect(viewModel.showingExportError == false)
    }

    @Test("exportData writes a CSV with a UTF-8 BOM and one row per transaction")
    func exportDataWritesCSV() throws {
        let context = try TestModelContainer.makeContext()
        let populated = MockData.makePopulatedAccount(in: context)
        let viewModel = SettingsViewModel(account: populated.account)

        viewModel.exportData(locale: Locale(identifier: "ru_RU"))

        let url = try #require(viewModel.exportedFileURL)
        createdFiles.append(url)
        #expect(viewModel.showingExportError == false)

        // String(contentsOf:encoding:.utf8) silently strips a leading BOM as an
        // encoding signature, so check the raw bytes to confirm it was written.
        let rawData = try Data(contentsOf: url)
        #expect(rawData.prefix(3) == Data([0xEF, 0xBB, 0xBF]))

        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.split(separator: "\n")
        #expect(lines.count == 1 + populated.transactions.count)
    }

    @Test("exportData on an empty account writes only the header row")
    func exportDataEmptyAccount() throws {
        let account = MockData.makeAccount()
        let viewModel = SettingsViewModel(account: account)

        viewModel.exportData(locale: Locale(identifier: "ru_RU"))

        let url = try #require(viewModel.exportedFileURL)
        createdFiles.append(url)

        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.split(separator: "\n")
        #expect(lines.count == 1)
    }

    @Test("exportData surfaces an error when the file name is too long to write")
    func exportDataFailure() {
        let account = MockData.makeAccount(name: String(repeating: "а", count: 300))
        let viewModel = SettingsViewModel(account: account)

        viewModel.exportData(locale: Locale(identifier: "ru_RU"))

        #expect(viewModel.exportedFileURL == nil)
        #expect(viewModel.showingExportError == true)
    }
}
