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

    @Test("Manual-scheme keys (service=<name>) are discovered under the CLI Added category")
    func discoversManualSchemeKeys() {
        let (vm, mock) = makeSUT()
        let name = uniqueEnvName()
        // `security add-generic-password -s KEY_NAME` 等で登録された manual スキームのキー (#160)
        mock.manualStore[name] = "secret"
        vm.loadKeys()

        let discovered = vm.keys.first { $0.envVarName == name }
        #expect(discovered != nil)
        #expect(discovered?.isConfigured == true)
        #expect(discovered?.builtinCategory == .cliAdded)
        #expect(discovered?.storage == .manual)
    }

    @Test("Editing a manual-only (CLI-managed) key fails closed instead of poisoning (#177)")
    func savingManualKeyFailsClosed() throws {
        let (vm, mock) = makeSUT()
        let name = uniqueEnvName()
        mock.manualStore[name] = "old-value"
        vm.loadKeys()
        let discovered = try #require(vm.keys.first { $0.envVarName == name })

        // in-process 編集は security 所有 manual アイテムを毒化するため拒否される。
        #expect(throws: KeychainError.self) {
            try vm.save(value: "new-value", for: discovered)
        }
        // 値は未変更（毒化も GUI 影コピーも起きない）
        #expect(mock.manualStore[name] == "old-value")
        #expect(mock.store[name] == nil)
    }

    @Test("Deleting a dual-scheme key removes both copies")
    func deletingRemovesBothSchemes() throws {
        let (vm, mock) = makeSUT()
        let name = uniqueEnvName()
        try mock.save(value: "app-value", for: name)
        mock.manualStore[name] = "manual-value"
        vm.loadKeys()
        let key = vm.keys.first { $0.envVarName == name }

        try vm.delete(key: key!)

        // 片方だけ残ると 2 段ルックアップで「復活」するため両方消える (#160)
        #expect(mock.store[name] == nil)
        #expect(mock.manualStore[name] == nil)
    }

    @Test("A key present in both schemes is not duplicated")
    func bothSchemesNotDuplicated() throws {
        let (vm, mock) = makeSUT()
        let name = uniqueEnvName()
        try mock.save(value: "app-value", for: name)
        mock.manualStore[name] = "manual-value"
        vm.loadKeys()
        #expect(vm.keys.filter { $0.envVarName == name }.count == 1)
    }

    @Test("A preset key backed only by a manual-scheme item shows as configured")
    func presetBackedByManualScheme() {
        let (vm, mock) = makeSUT()
        // プリセット名のキーが manual スキームにだけ存在する場合、2 段ルックアップで
        // configured になり、発見キーとして二重表示もされない (#160)。
        mock.manualStore["ANTHROPIC_API_KEY"] = "secret"
        vm.loadKeys()
        let matches = vm.keys.filter { $0.envVarName == "ANTHROPIC_API_KEY" }
        #expect(matches.count == 1)
        #expect(matches.first?.service == .some(.anthropic))
        #expect(matches.first?.isConfigured == true)
        #expect(matches.first?.builtinCategory != .cliAdded)
    }

    @Test("Manual-scheme names that are not strict upper-snake-case are not surfaced")
    func invalidManualNamesNotSurfaced() {
        let (vm, mock) = makeSUT()
        // 他アプリ/システムのアイテムは対象外。EnvVarName.isValid が許す小文字混じり
        //（iCloud / AirPort 等の実在システム service 名）も manual 発見では弾く。
        // MockKeychainService.manualServices() は無条件で返すため、ViewModel 側の
        // EnvVarName.isManualSchemeCandidate ガードを検証する。
        mock.manualStore["com.example.app"] = "v"
        mock.manualStore["9INVALID"] = "v"
        mock.manualStore["iCloud"] = "v"
        mock.manualStore["BluetoothGlobal"] = "v"
        vm.loadKeys()
        #expect(!vm.keys.contains { $0.envVarName == "com.example.app" })
        #expect(!vm.keys.contains { $0.envVarName == "9INVALID" })
        #expect(!vm.keys.contains { $0.envVarName == "iCloud" })
        #expect(!vm.keys.contains { $0.envVarName == "BluetoothGlobal" })
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
        let (vm, mock) = makeSUT()
        try mock.save(value: "test", for: "GITHUB_TOKEN")
        vm.loadKeys()
        #expect(vm.configuredCount == 1)

        let githubKey = vm.keys.first { $0.service == .some(.github) }!
        try vm.delete(key: githubKey)
        #expect(vm.configuredCount == 0)
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
    func manualServices() -> [String] { [] }
}
