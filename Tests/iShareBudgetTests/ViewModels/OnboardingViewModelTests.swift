import Testing
@testable import iShareBudget

@MainActor
@Suite("OnboardingViewModel", .serialized)
struct OnboardingViewModelTests {
    private func makeViewModel(
        store: InMemoryKeyValueStore = InMemoryKeyValueStore()
    ) -> OnboardingViewModel {
        OnboardingViewModel(store: store)
    }

    @Test("starts on the first of four pages")
    func initialState() {
        let viewModel = makeViewModel()

        #expect(viewModel.pages.count == 4)
        #expect(viewModel.currentPage == 0)
        #expect(viewModel.isLastPage == false)
    }

    @Test("advance moves to the next page without completing onboarding")
    func advanceMovesForward() {
        let store = InMemoryKeyValueStore()
        let viewModel = makeViewModel(store: store)

        viewModel.advance()

        #expect(viewModel.currentPage == 1)
        #expect(store.bool(forKey: OnboardingViewModel.storageKey) == false)
    }

    @Test("advance on the last page marks onboarding as completed")
    func advanceOnLastPageCompletes() {
        let store = InMemoryKeyValueStore()
        let viewModel = makeViewModel(store: store)

        for _ in 0..<(viewModel.pages.count - 1) {
            viewModel.advance()
        }
        #expect(viewModel.isLastPage == true)

        viewModel.advance()

        #expect(store.bool(forKey: OnboardingViewModel.storageKey) == true)
    }

    @Test("skip marks onboarding as completed from any page")
    func skipCompletesImmediately() {
        let store = InMemoryKeyValueStore()
        let viewModel = makeViewModel(store: store)

        viewModel.skip()

        #expect(store.bool(forKey: OnboardingViewModel.storageKey) == true)
    }
}
