import Testing
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
