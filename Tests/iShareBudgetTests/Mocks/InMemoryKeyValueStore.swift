import Foundation
@testable import iShareBudget

final class InMemoryKeyValueStore: KeyValueStore {
    private var storage: [String: Any] = [:]

    init(seed: [String: Any] = [:]) {
        storage = seed
    }

    func bool(forKey key: String) -> Bool {
        storage[key] as? Bool ?? false
    }

    func string(forKey key: String) -> String? {
        storage[key] as? String
    }

    func stringArray(forKey key: String) -> [String]? {
        storage[key] as? [String]
    }

    func object(forKey key: String) -> Any? {
        storage[key]
    }

    func set(_ value: Any?, forKey key: String) {
        storage[key] = value
    }
}
