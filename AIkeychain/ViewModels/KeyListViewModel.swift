import Foundation
import Observation

/// サイドバーで選択可能なカテゴリ（プリセット + カスタム統合）
enum CategorySelection: Hashable {
    case all
    case builtin(KeyCategory)
    case custom(UUID)
    case activity
}

@Observable
final class KeyListViewModel {
    var keys: [APIKey] = []
    var selectedCategory: CategorySelection? = .all
    var searchText: String = ""
    var selectedKey: APIKey?
    var showingEditor = false
    var editingKey: APIKey?

    private let keychainService: KeychainServiceProtocol
    private let customStore: CustomKeyStore

    init(keychainService: KeychainServiceProtocol = KeychainService.shared,
         customStore: CustomKeyStore = .shared) {
        self.keychainService = keychainService
        self.customStore = customStore
        loadKeys()
    }

    var filteredKeys: [APIKey] {
        var result = keys

        if let selection = selectedCategory {
            switch selection {
            case .all, .activity:
                break // no filter
            case .builtin(let category):
                result = result.filter { $0.builtinCategory == category }
            case .custom(let id):
                result = result.filter { $0.customCategoryId == id }
            }
        }

        if !searchText.isEmpty {
            result = result.filter {
                $0.displayName.localizedCaseInsensitiveContains(searchText)
                || $0.envVarName.localizedCaseInsensitiveContains(searchText)
            }
        }

        return result
    }

    var configuredCount: Int {
        keys.filter(\.isConfigured).count
    }

    var pendingCount: Int {
        keys.count - configuredCount
    }

    func builtinCategoryCount(for category: KeyCategory) -> Int {
        keys.filter { $0.builtinCategory == category }.count
    }

    func builtinCategoryConfiguredCount(for category: KeyCategory) -> Int {
        keys.filter { $0.builtinCategory == category && $0.isConfigured }.count
    }

    func customCategoryCount(for id: UUID) -> Int {
        keys.filter { $0.customCategoryId == id }.count
    }

    func customCategoryConfiguredCount(for id: UUID) -> Int {
        keys.filter { $0.customCategoryId == id && $0.isConfigured }.count
    }

    func loadKeys() {
        // スキーム判定用の集合（値は読まないので承認 UI は出ない）。
        // 両スキームに存在する場合は 2 段ルックアップの優先順どおり .app 扱い。
        let guiAccounts = Set(keychainService.allAccounts())
        let manualOnly = Set(keychainService.manualServices()).subtracting(guiAccounts)

        func storage(for name: String) -> StorageScheme {
            manualOnly.contains(name) ? .manual : .app
        }

        // プリセットキー
        var allKeys: [APIKey] = ServiceType.allCases.map { service in
            APIKey(
                service: service,
                isConfigured: keychainService.exists(for: service.envVarName),
                storage: storage(for: service.envVarName)
            )
        }

        // カスタムキー
        for customKey in customStore.keys {
            allKeys.append(APIKey(
                customKey: customKey,
                isConfigured: keychainService.exists(for: customKey.envVarName),
                storage: storage(for: customKey.envVarName)
            ))
        }

        // CLI (`akc set`) で追加され、プリセットにもカスタム索引にも無い Keychain キーを
        // 発見して「コマンド追加」カテゴリに出す（種別不明のためまとめて表示 / #153）。
        // env 変数名の形（EnvVarName.isValid）のみ採用し、内部用アイテムや
        // シェル export で壊れる名前は除外する。
        // known は発見ループ中も更新する。guiAccounts は Set なので同名アカウントの
        // 重複は既に畳まれているが、insert の成否での二重追加防止は維持（Codex #2）。
        var known = Set(allKeys.map(\.envVarName))
        for account in guiAccounts
        where EnvVarName.isValid(account) && known.insert(account).inserted {
            let discovered = CustomKey(
                envVarName: account,
                displayName: account,
                categoryId: KeyCategory.cliAdded.stableId
            )
            allKeys.append(APIKey(customKey: discovered, isConfigured: true))
        }

        // manual スキーム (service=<キー名>) のキーも同様に発見する (#160)。
        // `security add-generic-password -s KEY_NAME` による手動登録や、既存 manual
        // エントリを `akc set` が更新した場合はこちらにしか存在しない。値の解決は
        // KeychainService の 2 段ルックアップ (GUI → manual) が引き受けるため、
        // GUI からは他の発見キーと同じに扱える。名前は厳格形（大文字スネークケース）
        // のみ採用 — 緩くすると iCloud 等のシステムアイテムを誤検出する。
        for svc in keychainService.manualServices()
        where EnvVarName.isManualSchemeCandidate(svc) && known.insert(svc).inserted {
            let discovered = CustomKey(
                envVarName: svc,
                displayName: svc,
                categoryId: KeyCategory.cliAdded.stableId
            )
            allKeys.append(APIKey(customKey: discovered, isConfigured: true, storage: .manual))
        }

        keys = allKeys
    }

    func retrieveValue(for key: APIKey) -> String? {
        try? keychainService.retrieve(for: key.envVarName)
    }

    func save(value: String, for key: APIKey) throws {
        try keychainService.save(value: value, for: key.envVarName)
        loadKeys()
    }

    func delete(key: APIKey) throws {
        try keychainService.delete(for: key.envVarName)
        if let customKey = key.customKey {
            customStore.deleteKey(customKey.id)
        }
        loadKeys()
    }

    func addNewKey() {
        editingKey = nil
        showingEditor = true
    }

    func editKey(_ key: APIKey) {
        editingKey = key
        showingEditor = true
    }
}
