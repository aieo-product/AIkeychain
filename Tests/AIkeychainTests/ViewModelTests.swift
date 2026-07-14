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

    @Test("Editing a discovered key's category persists across reload (via override)")
    func editingDiscoveredKeyPersistsCategory() throws {
        let (vm, mock) = makeSUT()
        let name = uniqueEnvName()
        try mock.save(value: "secret", for: name)
        vm.loadKeys()
        let discovered = try #require(vm.keys.first { $0.envVarName == name })
        defer {
            // .shared に書いた override を後始末する
            CustomKeyStore.shared.setCategoryOverride(envVarName: name, value: nil)
            CustomKeyStore.shared.setIconOverride(envVarName: name, icon: nil)
        }

        // 発見キーをエディタで「開発ツール」に付け替えて保存
        let editor = KeyEditorViewModel(editingKey: discovered, keychainService: mock)
        editor.selectedCategorySelection = .builtin(.devTools)
        try editor.save()

        // 再読込しても .cliAdded に戻らず devTools を維持する
        vm.loadKeys()
        let after = vm.keys.first { $0.envVarName == name }
        #expect(after?.builtinCategory == .devTools)
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
        let (vm, mock) = makeSUT()
        let name = uniqueEnvName()
        try mock.save(value: "secret", for: name)
        vm.loadKeys()
        let discovered = try #require(vm.keys.first { $0.envVarName == name })

        // エディタで環境変数名を書き換えて保存しても、rename は起きない
        let editor = KeyEditorViewModel(editingKey: discovered, keychainService: mock)
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

    @Test("A discovered key moved to a custom category uses that category's color")
    func discoveredKeyMovedToCustomCategoryUsesItsColor() throws {
        let (vm, mock) = makeSUT()
        let name = uniqueEnvName()
        // テスト用カスタムカテゴリを .shared に用意
        let cat = CustomCategory(name: "CLI_Test_Cat_\(UUID().uuidString.prefix(6))", colorHex: 0x123456)
        CustomKeyStore.shared.addCategory(cat)
        try mock.save(value: "secret", for: name)
        vm.loadKeys()
        let discovered = try #require(vm.keys.first { $0.envVarName == name })
        defer {
            CustomKeyStore.shared.setCategoryOverride(envVarName: name, value: nil)
            CustomKeyStore.shared.setIconOverride(envVarName: name, icon: nil)
            CustomKeyStore.shared.deleteCategory(cat.id)
        }

        let editor = KeyEditorViewModel(editingKey: discovered, keychainService: mock)
        editor.selectedCategorySelection = .custom(cat.id)
        try editor.save()

        vm.loadKeys()
        let after = try #require(vm.keys.first { $0.envVarName == name })
        #expect(after.categoryColor == cat.color)
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
}
