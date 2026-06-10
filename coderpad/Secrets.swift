//
//  Secrets.swift
//  coderpad
//
//  Keychain-backed store for the CoderPad API key.
//

import Foundation
import Security
import SwiftUI

enum Keychain {
    static let service = "com.coderpad.app"
    static let account = "apiKey"

    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attrs: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

@Observable
final class APIKeyStore {
    static let shared = APIKeyStore()

    var apiKey: String {
        didSet {
            if apiKey.isEmpty {
                Keychain.delete()
            } else {
                Keychain.write(apiKey)
            }
        }
    }

    private init() {
        let legacyDefaultsKey = "coderPadAPIKey"
        if let stored = Keychain.read(), !stored.isEmpty {
            apiKey = stored
        } else if let legacy = UserDefaults.standard.string(forKey: legacyDefaultsKey), !legacy.isEmpty {
            Keychain.write(legacy)
            UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
            apiKey = legacy
        } else {
            apiKey = ""
        }
    }
}
