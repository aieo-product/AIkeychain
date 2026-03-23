import Testing
@testable import AIkeychain

@Suite("KeyListViewModel Tests")
struct KeyListViewModelTests {

    private func makeSUT() -> (KeyListViewModel, MockKeychainService) {
        let mock = MockKeychainService()
        let vm = KeyListViewModel(keychainService: mock)
        return (vm, mock)
    }

    @Test("Loads all service types as keys")
    func loadKeys() {
        let (vm, _) = makeSUT()
        #expect(vm.keys.count == ServiceType.allCases.count)
    }

    @Test("All keys start as unconfigured")
    func allUnconfigured() {
        let (vm, _) = makeSUT()
        #expect(vm.configuredCount == 0)
        #expect(vm.pendingCount == ServiceType.allCases.count)
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
        vm.selectedCategory = .ai
        let aiServices = ServiceType.allCases.filter { $0.category == .ai }
        #expect(vm.filteredKeys.count == aiServices.count)
    }

    @Test("Search filters by display name")
    func searchByName() {
        let (vm, _) = makeSUT()
        vm.searchText = "Anthropic"
        #expect(vm.filteredKeys.count == 1)
        #expect(vm.filteredKeys.first?.service == .anthropic)
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
        #expect(vm.categoryCount(for: .ai) == aiCount)
    }

    @Test("Delete key makes it unconfigured")
    func deleteKey() throws {
        let (vm, mock) = makeSUT()
        try mock.save(value: "test", for: "GITHUB_TOKEN")
        vm.loadKeys()
        #expect(vm.configuredCount == 1)

        let githubKey = vm.keys.first { $0.service == .github }!
        try vm.delete(key: githubKey)
        #expect(vm.configuredCount == 0)
    }
}
