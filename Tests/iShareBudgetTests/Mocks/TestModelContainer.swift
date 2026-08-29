import Foundation
import SwiftData
@testable import iShareBudget

@MainActor
enum TestModelContainer {
    static func make() throws -> ModelContainer {
        let schema = Schema([Account.self, Transaction.self, Category.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    static func makeContext() throws -> ModelContext {
        ModelContext(try make())
    }
}
