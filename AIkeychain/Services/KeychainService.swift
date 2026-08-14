import Foundation

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
    /// 主ストア（managed namespace, com.aieo.aikeychain.managed / #167）に存在する
    /// 全アカウント名を列挙する。CLI (`akc set`) で追加され GUI 索引に無いキーを
    /// 発見するために使う (#153)。秘密値は読まない（アカウント名のみ）。
    func allAccounts() -> [String]
    /// レガシー manual スキーム (service=<キー名>) で保存されているキー名を列挙する
    /// (#160)。`security add-generic-password -s KEY_NAME` による手動登録アイテムが
    /// 対象（#179 以降、akc set の書込先は managed であり manual には書かない）。
    /// npm CLI の判定規則と同じく env 変数名形式の service のみを manual と見なす。
    /// 秘密値は読まない。C5 (#172) の移行完了とともに廃止予定。
    func manualServices() -> [String]
}

// NOTE: 旧 in-process 実装 (`final class KeychainService`) は C3 #170 で削除した。
// GUI の secret 読み書きは SecurityCLIKeychainService（subprocess /usr/bin/security・
// managed namespace）が唯一の経路。in-proc SecItem* を secret 値に使ってはならない
// （PartitionID が分かれて akc run のヘッドレス読取を壊す — #167 の設計原理）。
// アプリ内部鍵（共有/署名鍵、KeyShareService）は例外: akc が読む対象ではなく、
// アプリだけが無音で読める in-proc 所有が正しい。

// MARK: - Mock for Previews and Tests

final class MockKeychainService: KeychainServiceProtocol {
    var store: [String: String] = [:]
    /// manual スキーム (service=<キー名>) 相当のアイテム (#160)
    var manualStore: [String: String] = [:]

    func save(value: String, for account: String) throws {
        store[account] = value
    }

    func retrieve(for account: String) throws -> String? {
        store[account] ?? manualStore[account]
    }

    func retrieveNoninteractive(for account: String) throws -> String? {
        store[account] ?? manualStore[account]
    }

    func delete(for account: String) throws {
        store.removeValue(forKey: account)
        manualStore.removeValue(forKey: account)
    }

    func exists(for account: String) -> Bool {
        store[account] != nil || manualStore[account] != nil
    }

    func allAccounts() -> [String] {
        Array(store.keys)
    }

    func manualServices() -> [String] {
        Array(manualStore.keys)
    }
}
