import Foundation
@testable import iShareBudget

@MainActor
final class MockPendingShareClearer: PendingShareClearing {
    private(set) var clearCount = 0

    func clearPendingShare() {
        clearCount += 1
    }
}
