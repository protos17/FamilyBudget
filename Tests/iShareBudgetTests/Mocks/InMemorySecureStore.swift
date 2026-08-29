import Foundation
@testable import iShareBudget

final class InMemorySecureStore: SecureStore {
    private var storage: [String: String] = [:]

    init(seed: [String: String] = [:]) {
        storage = seed
    }

    func load(forKey key: String) -> String? {
        storage[key]
    }

    func save(_ value: String, forKey key: String) {
        storage[key] = value
    }

    func delete(forKey key: String) {
        storage.removeValue(forKey: key)
    }
}
