import Foundation
import Security
import LocalAuthentication

enum KeychainError: LocalizedError {
    case duplicateItem
    case itemNotFound
    case invalidData
    case invalidAccount
    case interactionRequired
    /// The item is owned by `/usr/bin/security` (registered via the `akc` CLI or a
    /// manual `security add-generic-password`). An in-process edit from the GUI would
    /// silently poison it — leaving `akc run` unable to read it — so we fail closed
    /// and tell the user to edit it via the CLI instead. See issue #177.
    case cliManaged(String)
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .duplicateItem: "This key already exists in the Keychain."
        case .itemNotFound: "Key not found in the Keychain."
        case .invalidData: "Failed to encode/decode the key data."
        case .invalidAccount: "Invalid key name. Use only letters, digits and underscores (must start with a letter or underscore)."
        case .interactionRequired: "Keychain access requires user interaction (consent or unlock), which is unavailable in this context."
        case .cliManaged(let account): "\(account) is managed by the akc CLI. Change its value from the terminal with: akc set \(account)"
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

    /// アイテムの存在を **属性のみ** で確認する（値を読まない）。
    /// 値読み取り (kSecReturnData) は security 所有アイテムで ~7 秒ブロックして
    /// SecurityAgent を起動する（#177 の実測 E6-1）が、属性照会はプロンプト無しで
    /// 安全（loadKeys と同じ）。
    private func itemExists(matching base: [String: Any]) throws -> Bool {
        var query = base
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnAttributes as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess: return true
        case errSecItemNotFound: return false
        default: throw KeychainError.unexpectedStatus(status)
        }
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

        // #177: 既存アイテムへの in-process SecItemUpdate は、そのアイテムが
        // /usr/bin/security 所有（`akc set` / 手動 security 登録）の場合、**無音で成功
        // するのに所有権を毒化し、以後 `akc run` がヘッドレスで読めなくなる**（実測 E6-4）。
        // よって update を使わず、SecItemDelete を「プロンプトを出さない所有権プローブ」
        // として使う: 削除に失敗（-25244 等）= security 所有 → in-process 編集は毒化する
        // ので **アイテムを変更せず fail-closed**（`akc set` で編集するよう案内）。
        // 削除成功 = GUI 所有 → 新しい値で再作成する。
        let appQuery = baseQuery(for: account)

        if try itemExists(matching: appQuery) {
            let deleteStatus = SecItemDelete(appQuery as CFDictionary)
            guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
                // -25244（GUI からは削除できない = security 所有）を含む全ての失敗で
                // 毒化を避けるため fail-closed。アイテムは未変更（削除に失敗している）。
                throw KeychainError.cliManaged(account)
            }
        } else if EnvVarName.isManualSchemeCandidate(account),
                  try itemExists(matching: manualQuery(for: account)) {
            // manual スキーム (service=<KEY>) のキーは実運用上ほぼ security 所有
            // （手動 security 登録 / `akc set` の manual 更新）。in-process 編集は毒化する
            // ため、削除を試みず fail-closed（#163 の manual in-place 更新を置き換える）。
            throw KeychainError.cliManaged(account)
        }

        // 新規キー、または GUI 所有アイテムの削除成功後 → GUI スキームに追加
        var addQuery = appQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.unexpectedStatus(addStatus)
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
    /// `/usr/bin/security` 所有（`akc set` / 手動登録）を模すアカウント。実装では
    /// in-process SecItemDelete が -25244 で失敗するケース。save() は fail-closed する (#177)。
    var securityOwnedAccounts: Set<String> = []

    func save(value: String, for account: String) throws {
        // #177: 実装と同じ fail-closed 契約。
        // (1) security 所有アイテム（app スキームだが CLI/手動作成）→ in-process 編集は
        //     毒化するため cliManaged で拒否。
        // (2) manual スキームにのみ存在するキーも実運用上 security 所有 → 拒否。
        if securityOwnedAccounts.contains(account) {
            throw KeychainError.cliManaged(account)
        }
        if store[account] == nil, manualStore[account] != nil {
            throw KeychainError.cliManaged(account)
        }
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
