//
//  KeyValueStore.swift
//  iShareBudget
//
//  Protocol for dependency injection in tests.
//

import Foundation

protocol KeyValueStore: AnyObject {
    func bool(forKey key: String) -> Bool
    func string(forKey key: String) -> String?
    func stringArray(forKey key: String) -> [String]?
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: KeyValueStore {}
