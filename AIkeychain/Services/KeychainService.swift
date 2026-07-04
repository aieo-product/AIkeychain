import Foundation
import Security
import LocalAuthentication

enum KeychainError: LocalizedError {
    case duplicateItem
    case itemNotFound
    case invalidData
    case invalidAccount
    case interactionRequired
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .duplicateItem: "This key already exists in the Keychain."
        case .itemNotFound: "Key not found in the Keychain."
        case .invalidData: "Failed to encode/decode the key data."
        case .invalidAccount: "Invalid key name. Use only letters, digits and underscores (must start with a letter or underscore)."
        case .interactionRequired: "Keychain access requires user interaction (consent or unlock), which is unavailable in this context."
        case .unexpectedStatus(let status): "Keychain error: \(status)"
        }
    }
}

protocol KeychainServiceProtocol {
    func save(value: String, for account: String) throws
    func retrieve(for account: String) throws -> String?
    /// Read without ever presenting authentication/consent UI.
    /// Throws `KeychainError.interactionRequired` instead of blocking when macOS
    /// would otherwise show a SecurityAgent prompt — required for an unattended
    /// background proxy that must never hang on a keychain read.
    func retrieveNoninteractive(for account: String) throws -> String?
    func delete(for account: String) throws
    func exists(for account: String) -> Bool
}

final class KeychainService: KeychainServiceProtocol {
    static let shared = KeychainService()

    private let service = "com.aieo.aikeychain"

    private init() {}

    private func baseQuery(for account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func save(value: String, for account: String) throws {
        // シンクでの一元検証: どの ingress（手動エディタ / .env インポート /
        // キー共有インポート）経由でも、シェル export に安全な名前だけを Keychain に
        // 書き込む。共有ファイル等の外部由来 envVarName によるシェルインジェクション
        // （ZshrcExporter が `export \(name)=...` へ生値補間）を根本で防ぐ (#116)。
        guard EnvVarName.isValid(account) else {
            throw KeychainError.invalidAccount
        }
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.invalidData
        }

        // Try to update first
        let query = baseQuery(for: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            // Item doesn't exist, add it
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }

    func retrieve(for account: String) throws -> String? {
        var query = baseQuery(for: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }

        guard let data = result as? Data, let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }

        return string
    }

    func retrieveNoninteractive(for account: String) throws -> String? {
        var query = baseQuery(for: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        // Fail fast instead of presenting (and blocking on) a consent/auth prompt.
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }
        if status == errSecInteractionNotAllowed {
            throw KeychainError.interactionRequired
        }
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
        guard let data = result as? Data, let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        return string
    }

    func delete(for account: String) throws {
        let query = baseQuery(for: account)
        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func exists(for account: String) -> Bool {
        var query = baseQuery(for: account)
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
}

// MARK: - Mock for Previews and Tests

final class MockKeychainService: KeychainServiceProtocol {
    var store: [String: String] = [:]

    func save(value: String, for account: String) throws {
        store[account] = value
    }

    func retrieve(for account: String) throws -> String? {
        store[account]
    }

    func retrieveNoninteractive(for account: String) throws -> String? {
        store[account]
    }

    func delete(for account: String) throws {
        store.removeValue(forKey: account)
    }

    func exists(for account: String) -> Bool {
        store[account] != nil
    }
}
