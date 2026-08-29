import Testing
import Foundation
@testable import iShareBudget

@MainActor
@Suite("CloudKitShareHandlerViewModel")
struct CloudKitShareHandlerViewModelTests {
    @Test("initial state")
    func initialState() {
        let viewModel = CloudKitShareHandlerViewModel()

        #expect(viewModel.isAccepting == false)
        #expect(viewModel.showingAccepted == false)
        #expect(viewModel.showingError == false)
    }

    @Test("acceptShare(nil, context:) leaves state untouched")
    func acceptShareNilMetadata() async throws {
        let context = try TestModelContainer.makeContext()
        let pendingShare = MockPendingShareClearer()
        let viewModel = CloudKitShareHandlerViewModel(pendingShare: pendingShare)

        await viewModel.acceptShare(nil, context: context)

        #expect(viewModel.isAccepting == false)
        #expect(viewModel.showingAccepted == false)
        #expect(pendingShare.clearCount == 0)
    }

    @Test("performAccept success populates the accepted list name")
    func performAcceptSuccess() async {
        let pendingShare = MockPendingShareClearer()
        let viewModel = CloudKitShareHandlerViewModel(pendingShare: pendingShare)
        let account = MockData.makeAccount(name: "Общий бюджет")

        await viewModel.performAccept { account }

        #expect(viewModel.acceptedListName == "Общий бюджет")
        #expect(viewModel.showingAccepted == true)
        #expect(viewModel.isAccepting == false)
        #expect(pendingShare.clearCount == 1)
    }

    @Test("performAccept failure surfaces an error message")
    func performAcceptFailure() async {
        struct SomeError: Error, LocalizedError {
            var errorDescription: String? { "boom" }
        }
        let pendingShare = MockPendingShareClearer()
        let viewModel = CloudKitShareHandlerViewModel(pendingShare: pendingShare)

        await viewModel.performAccept { throw SomeError() }

        #expect(viewModel.showingError == true)
        #expect(viewModel.errorMessage.contains("boom"))
        #expect(viewModel.isAccepting == false)
        #expect(pendingShare.clearCount == 1)
    }
}
