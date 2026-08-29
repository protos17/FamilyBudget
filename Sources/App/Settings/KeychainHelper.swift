//
//  KeychainHelper.swift
//  FamilyBudget
//
//  Secure storage for sensitive strings (API keys).
//

import Foundation
import Security

/// Protocol for dependency injection in tests
protocol SecureStore {
    func load(forKey key: String) -> String?
    func save(_ value: String, forKey key: String)
    func delete(forKey key: String)
}

/// Thin wrapper adapting the static `KeychainHelper` API to `SecureStore`
struct KeychainSecureStore: SecureStore {
    func load(forKey key: String) -> String? { KeychainHelper.load(forKey: key) }
    func save(_ value: String, forKey key: String) { KeychainHelper.save(value, forKey: key) }
    func delete(forKey key: String) { KeychainHelper.delete(forKey: key) }
}

enum KeychainHelper {
    private static let service = Bundle.main.bundleIdentifier ?? "ru.protos.familybudget"

    static func save(_ value: String, forKey key: String) {
        guard let data = value.data(using: .utf8) else { return }

        // Delete existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new item
        let addQuery: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String:   data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func load(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
