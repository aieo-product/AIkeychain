import Testing
import Foundation
@testable import AIkeychain

@Suite("KeyListViewModel Tests")
struct KeyListViewModelTests {

    private func makeSUT() -> (KeyListViewModel, MockKeychainService) {
        let mock = MockKeychainService()
        // CustomKeyStore.shared はグローバル状態なので、カスタムキーが残っていると
        // vm.keys.count がプリセット数 + カスタム数になる。テストではカスタム数も考慮する。
        let vm = KeyListViewModel(keychainService: mock)
        return (vm, mock)
    }

    /// プリセット + カスタム合計数（現在のグローバル状態に依存）
    private var expectedKeyCount: Int {
        ServiceType.allCases.count + CustomKeyStore.shared.keys.count
    }

    @Test("Loads all service types as keys")
    func loadKeys() {
        let (vm, _) = makeSUT()
        #expect(vm.keys.count == expectedKeyCount)
    }

    @Test("All keys start as unconfigured")
    func allUnconfigured() {
        let (vm, _) = makeSUT()
        #expect(vm.configuredCount == 0)
        #expect(vm.pendingCount == expectedKeyCount)
    }

    @Test("Configured count updates after save")
    func configuredCountAfterSave() throws {
        let (vm, mock) = makeSUT()
        try mock.save(value: "test", for: "ANTHROPIC_API_KEY")
        vm.loadKeys()
        #expect(vm.configuredCount == 1)
    }

    @Test("Filter by category")
    func filterByCategory() {
        let (vm, _) = makeSUT()
        vm.selectedCategory = .builtin(.ai)
        let aiServices = ServiceType.allCases.filter { $0.category == .ai }
        #expect(vm.filteredKeys.count == aiServices.count)
    }

    @Test("Search filters by display name")
    func searchByName() {
        let (vm, _) = makeSUT()
        vm.searchText = "Anthropic"
        let matches = vm.filteredKeys.filter { $0.displayName.contains("Anthropic") }
        #expect(matches.count >= 1)
        #expect(matches.contains { $0.service == .some(.anthropic) })
    }

    @Test("Search filters by env var name")
    func searchByEnvVar() {
        let (vm, _) = makeSUT()
        vm.searchText = "GITHUB_TOKEN"
        #expect(vm.filteredKeys.count == 1)
        #expect(vm.filteredKeys.first?.service == .github)
    }

    @Test("Category count returns correct number")
    func categoryCount() {
        let (vm, _) = makeSUT()
        let aiCount = ServiceType.allCases.filter { $0.category == .ai }.count
        #expect(vm.builtinCategoryCount(for: .ai) == aiCount)
    }

    /// CustomKeyStore.shared のグローバル状態と衝突しない、テストごとに一意な env 変数名。
    /// （APIKey の分類は .shared 参照のため、既存 custom キーと同名だと偽陽性になる — #6 対策）
    private func uniqueEnvName() -> String {
        "CLI_TEST_" + UUID().uuidString.replacingOccurrences(of: "-", with: "_")
    }

    /// 分離した UserDefaults スイートで CustomKeyStore を作る。テストが
    /// グローバルな `CustomKeyStore.shared`（`.standard`）を書き換えないための土台。
    /// swift-testing は既定で並列実行するため、`.shared` を書くテストは他テストの
    /// `.shared` 読取と競合してクラッシュし得る（ModelTests と同じ隔離パターンに揃える）。
    private func isolatedStore() -> (CustomKeyStore, UserDefaults, String) {
        let suite = "test-keylist-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (CustomKeyStore(defaults: defaults), defaults, suite)
    }

    @Test("CLI-added keychain keys are discovered under the CLI Added category")
    func discoversCliAddedKeys() throws {
        let (vm, mock) = makeSUT()
        let name = uniqueEnvName()
        // プリセットにもカスタムにも無い、CLI (akc set) 由来の Keychain キー。
        try mock.save(value: "secret", for: name)
        vm.loadKeys()

        let discovered = vm.keys.first { $0.envVarName == name }
        #expect(discovered != nil)
        #expect(discovered?.isConfigured == true)
        #expect(discovered?.builtinCategory == .cliAdded)
        // 「コマンド追加」カテゴリでフィルタすると出てくる
        vm.selectedCategory = .builtin(.cliAdded)
        #expect(vm.filteredKeys.contains { $0.envVarName == name })
    }

    @Test("A discovered key shows the CLI Added category color, not gray")
    func discoveredKeyUsesCliAddedColor() throws {
        let (vm, mock) = makeSUT()
        let name = uniqueEnvName()
        try mock.save(value: "secret", for: name)
        vm.loadKeys()
        let discovered = vm.keys.first { $0.envVarName == name }
        #expect(discovered?.categoryColor == KeyCategory.cliAdded.color)
    }

    @Test("Editing a discovered key's category is persisted as an override")
    func editingDiscoveredKeyPersistsCategory() throws {
        let (store, defaults, suite) = isolatedStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let mock = MockKeychainService()
        let name = uniqueEnvName()
        try mock.save(value: "secret", for: name)
        let vm = KeyListViewModel(keychainService: mock, customStore: store)
        let discovered = try #require(vm.keys.first { $0.envVarName == name })

        // 発見キーをエディタで「開発ツール」に付け替えて保存
        let editor = KeyEditorViewModel(editingKey: discovered, keychainService: mock, customStore: store)
        editor.selectedCategorySelection = .builtin(.devTools)
        try editor.save()

        // 発見キー（customStore に無い合成キー）の分類変更は override として永続化される。
        // → 再読込後も APIKey.builtinCategory が override を優先解決し devTools を維持する。
        #expect(store.overriddenCategory(for: name) == .builtin(.devTools))
    }

    @Test("A preset key stored via CLI is not duplicated as a discovered key")
    func presetStoredViaCliIsNotDuplicated() throws {
        let (vm, mock) = makeSUT()
        // プリセットの envVarName を CLI で保存しても、発見キーとして二重表示しない。
        try mock.save(value: "secret", for: "ANTHROPIC_API_KEY")
        vm.loadKeys()

        let matches = vm.keys.filter { $0.envVarName == "ANTHROPIC_API_KEY" }
        #expect(matches.count == 1)
        #expect(matches.first?.service == .some(.anthropic))
        // .cliAdded ではなくプリセットのカテゴリに属する
        #expect(matches.first?.builtinCategory != .cliAdded)
    }

    @Test("Non-env-var-shaped keychain accounts are not surfaced")
    func invalidNamesNotSurfaced() throws {
        let (vm, mock) = makeSUT()
        // env 変数名として無効な名前（先頭数字 / ハイフン）は一覧に出さない。
        try mock.save(value: "v", for: "9INVALID")
        try mock.save(value: "v", for: "has-hyphen")
        vm.loadKeys()
        #expect(!vm.keys.contains { $0.envVarName == "9INVALID" })
        #expect(!vm.keys.contains { $0.envVarName == "has-hyphen" })
    }


    @Test("Editing an existing key does not rename it (no orphaned duplicate)")
    func editingDoesNotRenameKey() throws {
        let (store, defaults, suite) = isolatedStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let mock = MockKeychainService()
        let name = uniqueEnvName()
        try mock.save(value: "secret", for: name)
        let vm = KeyListViewModel(keychainService: mock, customStore: store)
        let discovered = try #require(vm.keys.first { $0.envVarName == name })

        // エディタで環境変数名を書き換えて保存しても、rename は起きない
        let editor = KeyEditorViewModel(editingKey: discovered, keychainService: mock, customStore: store)
        editor.selectedCategorySelection = .builtin(.devTools)
        editor.envVarName = name + "_RENAMED"
        try editor.save()

        vm.loadKeys()
        // 新名は作られず、旧名だけが残る（二重表示・無確認上書きを防ぐ）
        #expect(!vm.keys.contains { $0.envVarName == name + "_RENAMED" })
        #expect(vm.keys.contains { $0.envVarName == name })
        #expect(mock.exists(for: name))
        #expect(!mock.exists(for: name + "_RENAMED"))
    }

    @Test("Editing a discovered key into a custom category persists the override")
    func editingDiscoveredKeyPersistsCustomCategory() throws {
        let (store, defaults, suite) = isolatedStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let mock = MockKeychainService()
        let name = uniqueEnvName()
        let cat = CustomCategory(name: "CLI_Test_Cat", colorHex: 0x123456)
        store.addCategory(cat)
        try mock.save(value: "secret", for: name)
        let vm = KeyListViewModel(keychainService: mock, customStore: store)
        let discovered = try #require(vm.keys.first { $0.envVarName == name })

        let editor = KeyEditorViewModel(editingKey: discovered, keychainService: mock, customStore: store)
        editor.selectedCategorySelection = .custom(cat.id)
        try editor.save()

        // 発見キーをカスタムカテゴリへ移動 → override として永続化される（categoryColor は
        // この customCategoryId 経由で当該カテゴリ色を解決する。色解決自体は
        // discoveredKeyUsesCliAddedColor でも担保）。
        #expect(store.overriddenCategory(for: name) == .custom(cat.id))
    }

    @Test("Duplicate accounts from enumeration are surfaced only once")
    func dedupesDuplicateDiscoveredAccounts() {
        let name = "CLI_DUP_" + UUID().uuidString.replacingOccurrences(of: "-", with: "_")
        let stub = DupAccountsKeychainService(accounts: [name, name])
        let vm = KeyListViewModel(keychainService: stub)
        #expect(vm.keys.filter { $0.envVarName == name }.count == 1)
    }

    @Test("Delete key makes it unconfigured")
    func deleteKey() throws {
        // delete(key:) は上書きを消すため、.shared を書き換えないよう isolated store を使う（#210）
        let (store, defaults, suite) = isolatedStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let mock = MockKeychainService()
        let vm = KeyListViewModel(keychainService: mock, customStore: store)
        try mock.save(value: "test", for: "GITHUB_TOKEN")
        vm.loadKeys()
        #expect(vm.configuredCount == 1)

        let githubKey = vm.keys.first { $0.service == .some(.github) }!
        try vm.delete(key: githubKey)
        #expect(vm.configuredCount == 0)
    }

    // MARK: - 削除後状態の統一 (#210)

    @Test("delete(key:) clears category/icon overrides and the stored custom definition (#210)")
    func listDeleteClearsOverridesAndDefinition() throws {
        let (store, defaults, suite) = isolatedStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let mock = MockKeychainService()
        let name = uniqueEnvName()
        let custom = CustomKey(envVarName: name, displayName: name,
                               categoryId: KeyCategory.devTools.stableId)
        store.addKey(custom)
        store.setCategoryOverride(envVarName: name, value: "builtin:\(KeyCategory.ai.rawValue)")
        store.setIconOverride(envVarName: name, icon: "flame")
        store.setCategoryOverride(envVarName: "GITHUB_TOKEN", value: "builtin:\(KeyCategory.ai.rawValue)")
        store.setIconOverride(envVarName: "GITHUB_TOKEN", icon: "star.fill")
        try mock.save(value: "secret", for: name)
        try mock.save(value: "ghp_x", for: "GITHUB_TOKEN")

        let vm = KeyListViewModel(keychainService: mock, customStore: store)
        try vm.delete(key: try #require(vm.keys.first { $0.envVarName == name }))
        try vm.delete(key: try #require(vm.keys.first { $0.service == .some(.github) }))

        #expect(mock.store[name] == nil)
        #expect(!store.keys.contains { $0.id == custom.id })
        #expect(store.overriddenCategory(for: name) == nil)
        #expect(store.overriddenIcon(for: name) == nil)
        #expect(store.overriddenCategory(for: "GITHUB_TOKEN") == nil)
        #expect(store.overriddenIcon(for: "GITHUB_TOKEN") == nil)
        // 永続化にも残らない（同名再登録で古い上書きが復活しない）
        let reloaded = CustomKeyStore(defaults: defaults)
        #expect(reloaded.categoryOverrides.isEmpty)
        #expect(reloaded.iconOverrides.isEmpty)
        #expect(!reloaded.keys.contains { $0.id == custom.id })
    }

    @Test("delete(key:) on a discovered (synthetic) or preset key leaves stored definitions untouched (#210)")
    func listDeleteSyntheticAndPresetKeepDefinitions() throws {
        let (store, defaults, suite) = isolatedStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let mock = MockKeychainService()
        let other = CustomKey(envVarName: uniqueEnvName(), displayName: "Other",
                              categoryId: KeyCategory.ai.stableId)
        store.addKey(other)
        let cliName = uniqueEnvName()
        try mock.save(value: "secret", for: cliName)
        try mock.save(value: "ghp_x", for: "GITHUB_TOKEN")

        let vm = KeyListViewModel(keychainService: mock, customStore: store)
        let discovered = try #require(vm.keys.first { $0.envVarName == cliName })
        #expect(discovered.builtinCategory == .cliAdded)
        try vm.delete(key: discovered)
        try vm.delete(key: try #require(vm.keys.first { $0.service == .some(.github) }))

        #expect(mock.store[cliName] == nil)
        #expect(mock.store["GITHUB_TOKEN"] == nil)
        #expect(store.keys == [other])
        #expect(CustomKeyStore(defaults: defaults).keys == [other])
    }

    @Test("If the keychain delete fails, delete(key:) keeps overrides and the definition (#210)")
    func listDeleteFailureKeepsMetadata() throws {
        let (store, defaults, suite) = isolatedStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let failing = FailingDeleteKeychainService()
        let name = uniqueEnvName()
        let custom = CustomKey(envVarName: name, displayName: name,
                               categoryId: KeyCategory.devTools.stableId)
        store.addKey(custom)
        store.setCategoryOverride(envVarName: name, value: "builtin:\(KeyCategory.ai.rawValue)")
        store.setIconOverride(envVarName: name, icon: "flame")
        try failing.save(value: "secret", for: name)

        let vm = KeyListViewModel(keychainService: failing, customStore: store)
        let key = try #require(vm.keys.first { $0.envVarName == name })
        #expect(throws: KeychainError.self) { try vm.delete(key: key) }

        #expect(failing.store[name] == "secret")
        #expect(store.keys.contains { $0.id == custom.id })
        #expect(store.overriddenCategory(for: name) == .builtin(.ai))
        #expect(store.overriddenIcon(for: name) == "flame")
    }

    @Test("KeyListViewModel.delete(key:) and KeyEditorViewModel.deleteKey() leave identical state (#210)")
    func bothDeletePathsLeaveSameState() throws {
        let custom = CustomKey(envVarName: uniqueEnvName(), displayName: "Custom",
                               categoryId: KeyCategory.devTools.stableId)
        let other = CustomKey(envVarName: uniqueEnvName(), displayName: "Other",
                              categoryId: KeyCategory.ai.stableId)
        let cliName = uniqueEnvName()

        /// 同一の初期状態（カスタム・プリセット・CLI 発見キー、それぞれ上書き付き）を作る
        func seed() throws -> (CustomKeyStore, UserDefaults, String, MockKeychainService) {
            let (store, defaults, suite) = isolatedStore()
            store.addKey(custom)
            store.addKey(other)
            for name in [custom.envVarName, "GITHUB_TOKEN", cliName, other.envVarName] {
                store.setCategoryOverride(envVarName: name, value: "builtin:\(KeyCategory.ai.rawValue)")
                store.setIconOverride(envVarName: name, icon: "flame")
            }
            let mock = MockKeychainService()
            for name in [custom.envVarName, "GITHUB_TOKEN", cliName, other.envVarName] {
                try mock.save(value: "v", for: name)
            }
            return (store, defaults, suite, mock)
        }
        let targets = [custom.envVarName, "GITHUB_TOKEN", cliName]

        // 経路 A: 一覧 ViewModel
        let (storeA, defaultsA, suiteA, mockA) = try seed()
        defer { defaultsA.removePersistentDomain(forName: suiteA) }
        let listVM = KeyListViewModel(keychainService: mockA, customStore: storeA)
        for name in targets {
            try listVM.delete(key: try #require(listVM.keys.first { $0.envVarName == name }))
        }

        // 経路 B: エディタ ViewModel（#202 で修正済み = 正）
        let (storeB, defaultsB, suiteB, mockB) = try seed()
        defer { defaultsB.removePersistentDomain(forName: suiteB) }
        let listForB = KeyListViewModel(keychainService: mockB, customStore: storeB)
        for name in targets {
            let key = try #require(listForB.keys.first { $0.envVarName == name })
            try KeyEditorViewModel(editingKey: key, keychainService: mockB, customStore: storeB).deleteKey()
        }

        #expect(mockA.store == mockB.store)
        #expect(storeA.keys == storeB.keys)
        #expect(storeA.categoryOverrides == storeB.categoryOverrides)
        #expect(storeA.iconOverrides == storeB.iconOverrides)
        // 削除対象外（other）の上書き・定義だけが残る
        #expect(storeA.keys == [other])
        #expect(Set(storeA.categoryOverrides.keys) == [other.envVarName])
        #expect(Set(storeA.iconOverrides.keys) == [other.envVarName])
    }
}

/// `allAccounts()` が重複を返す状況を再現するテストダブル（辞書ベースの Mock では作れない）。
final class DupAccountsKeychainService: KeychainServiceProtocol {
    private let accounts: [String]
    init(accounts: [String]) { self.accounts = accounts }
    func save(value: String, for account: String) throws {}
    func retrieve(for account: String) throws -> String? { nil }
    func retrieveNoninteractive(for account: String) throws -> String? { nil }
    func delete(for account: String) throws {}
    func exists(for account: String) -> Bool { true }
    func allAccounts() -> [String] { accounts }
}
