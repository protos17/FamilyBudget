import Foundation
@testable import iShareBudget

@MainActor
final class MockUserIdentityService: UserIdentityProviding {
    var currentUserID: String? = "current-user"
    var isCloudKitAvailable: Bool = true
    var ownerResult: Bool = true
    var creatorResult: Bool = true

    func isCurrentUserOwner(of list: Account) -> Bool { ownerResult }
    func didCurrentUserCreate(_ item: Transaction) -> Bool { creatorResult }
}
