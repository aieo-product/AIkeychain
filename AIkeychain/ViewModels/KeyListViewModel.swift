import Foundation
import Observation

@Observable
final class KeyListViewModel {
    var keys: [APIKey] = []
    var selectedCategory: KeyCategory?
    var searchText: String = ""
    var selectedKey: APIKey?
    var showingEditor = false
    var editingKey: APIKey?

    private let keychainService: KeychainServiceProtocol

    init(keychainService: KeychainServiceProtocol = KeychainService.shared) {
        self.keychainService = keychainService
        loadKeys()
    }

    var filteredKeys: [APIKey] {
        var result = keys

        if let category = selectedCategory {
            result = result.filter { $0.service.category == category }
        }

        if !searchText.isEmpty {
            result = result.filter {
                $0.service.displayName.localizedCaseInsensitiveContains(searchText)
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

    func categoryCount(for category: KeyCategory) -> Int {
        keys.filter { $0.service.category == category }.count
    }

    func categoryConfiguredCount(for category: KeyCategory) -> Int {
        keys.filter { $0.service.category == category && $0.isConfigured }.count
    }

    func loadKeys() {
        keys = ServiceType.allCases.map { service in
            APIKey(
                service: service,
                isConfigured: keychainService.exists(for: service.envVarName)
            )
        }
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
