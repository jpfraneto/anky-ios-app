//
//  KeychainHelper.swift
//  Anky
//

import Foundation
import Security

enum KeychainHelper {
    private static let service = Bundle.main.bundleIdentifier ?? "com.jpfraneto.Anky"

    @discardableResult
    static func set(_ value: String, for key: String, synchronizable: Bool = false) -> Bool {
        set(Data(value.utf8), for: key, synchronizable: synchronizable)
    }

    @discardableResult
    static func set(_ value: Data, for key: String, synchronizable: Bool = false) -> Bool {
        delete(key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: value,
            kSecAttrAccessible as String: synchronizable ? kSecAttrAccessibleAfterFirstUnlock : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable as String: synchronizable
        ]

        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func get(_ key: String, synchronizable: Bool = false) -> String? {
        guard let data = getData(key, synchronizable: synchronizable) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func getData(_ key: String, synchronizable: Bool = false) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrSynchronizable as String: synchronizable
        ]

        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    @discardableResult
    static func delete(_ key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
