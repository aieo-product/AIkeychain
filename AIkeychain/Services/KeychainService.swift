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
    /// AI KeyChain の保存 service (com.aieo.aikeychain) に存在する全アカウント名を列挙する。
    /// CLI (`akc set`) で追加され GUI 索引に無いキーを発見するために使う (#153)。
    /// 秘密値は読まない（アカウント名のみ）。
    func allAccounts() -> [String]
    /// manual スキーム (service=<キー名>) で保存されているキー名を列挙する (#160)。
    /// `security add-generic-password -s KEY_NAME` による手動登録や、既存 manual
    /// エントリを `akc set` が更新した場合のアイテムが対象。npm CLI の判定規則と同じく
    /// env 変数名形式の service のみを manual と見なす。秘密値は読まない。
    func manualServices() -> [String]
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

    /// manual スキーム (service=<キー名>) のクエリ。acct はゆらぎがある（$USER /
    /// キー名 / 空）ため意図的にピン留めしない — #91 の CLI 側 2 段ルックアップと同じ。
    private func manualQuery(for account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: account,
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
            // GUI スキームに無く manual スキームにだけ存在するキーは、manual 側を
            // その場で更新する（CLI の setKey と同じ）。GUI 側へ新規追加してしまうと
            // 旧値を持つ manual アイテムが残り、manual を直接読む既存の .zshrc 行や
            // スクリプトがローテート前の値を使い続ける (#163 レビュー指摘)。
            if EnvVarName.isManualSchemeCandidate(account) {
                let manualStatus = SecItemUpdate(manualQuery(for: account) as CFDictionary,
                                                 attributes as CFDictionary)
                if manualStatus == errSecSuccess {
                    return
                }
                guard manualStatus == errSecItemNotFound else {
                    throw KeychainError.unexpectedStatus(manualStatus)
                }
            }

            // どちらにも無い新規キーは GUI スキームに追加
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
        // 2 段ルックアップ: GUI スキーム → manual スキーム (#91 の CLI 側と同じ順序 / #160)。
        // manual 側は厳格な名前形（大文字スネークケース）のときだけ照会し、
        // 他アプリ/システムのアイテムへ fallback が波及しないようにする。
        if let value = try copyValue(query: baseQuery(for: account)) {
            return value
        }
        guard EnvVarName.isManualSchemeCandidate(account) else { return nil }
        return try copyValue(query: manualQuery(for: account))
    }

    private func copyValue(query base: [String: Any], context: LAContext? = nil) throws -> String? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        if let context {
            query[kSecUseAuthenticationContext as String] = context
        }

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

    func retrieveNoninteractive(for account: String) throws -> String? {
        // Fail fast instead of presenting (and blocking on) a consent/auth prompt.
        let context = LAContext()
        context.interactionNotAllowed = true
        if let value = try copyValue(query: baseQuery(for: account), context: context) {
            return value
        }
        guard EnvVarName.isManualSchemeCandidate(account) else { return nil }
        return try copyValue(query: manualQuery(for: account), context: context)
    }

    func delete(for account: String) throws {
        // GUI スキームと manual スキームの両方を削除する（`akc delete` と同じ意味論）。
        // 片方だけ消すと 2 段ルックアップ (retrieve) がもう片方を解決し続け、
        // 「削除したのに残っている」状態になるため (#160)。manual 側は他ツール作成の
        // アイテムであり得るため、削除確認ダイアログ（KeyEditorView）が manual コピーの
        // 存在を事前警告する。
        // 順序は manual → GUI: 逆順だと manual 削除が失敗したとき GUI コピーだけが
        // 消え、古い manual 値が 2 段ルックアップで「復活」する（fail-closed 化）。
        // SecItemDelete は macOS では全一致アイテムを削除する。
        if EnvVarName.isManualSchemeCandidate(account) {
            let manualStatus = SecItemDelete(manualQuery(for: account) as CFDictionary)
            guard manualStatus == errSecSuccess || manualStatus == errSecItemNotFound else {
                throw KeychainError.unexpectedStatus(manualStatus)
            }
        }
        let guiStatus = SecItemDelete(baseQuery(for: account) as CFDictionary)
        guard guiStatus == errSecSuccess || guiStatus == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(guiStatus)
        }
    }

    func exists(for account: String) -> Bool {
        // 2 段ルックアップ (#160)。attributes 照会のみで値は読まないため承認 UI は出ない。
        var queries = [baseQuery(for: account)]
        if EnvVarName.isManualSchemeCandidate(account) {
            queries.append(manualQuery(for: account))
        }
        for base in queries {
            var query = base
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
                return true
            }
        }
        return false
    }

    func allAccounts() -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            return []
        }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    func manualServices() -> [String] {
        // service 指定なしで全 generic password の attributes を列挙し（値は読まないため
        // 承認 UI は出ない）、env 変数名形式の service を manual スキームと判定する。
        // npm CLI (cli/src/keychain.js) の dump-keychain 解析と同じ規則 (#160)。
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            return []
        }
        var seen = Set<String>()
        return items.compactMap { item -> String? in
            guard let svc = item[kSecAttrService as String] as? String,
                  svc != service,
                  EnvVarName.isManualSchemeCandidate(svc),
                  seen.insert(svc).inserted else { return nil }
            return svc
        }
    }
}

// MARK: - Mock for Previews and Tests

final class MockKeychainService: KeychainServiceProtocol {
    var store: [String: String] = [:]
    /// manual スキーム (service=<キー名>) 相当のアイテム (#160)
    var manualStore: [String: String] = [:]

    func save(value: String, for account: String) throws {
        // 実装と同じ意味論: manual にだけ存在するキーは manual 側を in-place 更新
        if store[account] == nil, manualStore[account] != nil {
            manualStore[account] = value
        } else {
            store[account] = value
        }
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
