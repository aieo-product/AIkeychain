import Foundation
import Observation

/// サイドバーで選択可能なカテゴリ（プリセット + カスタム統合）
enum CategorySelection: Hashable {
    case all
    case builtin(KeyCategory)
    case custom(UUID)
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
            case .all:
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
        // プリセットキー
        var allKeys: [APIKey] = ServiceType.allCases.map { service in
            APIKey(
                service: service,
                isConfigured: keychainService.exists(for: service.envVarName)
            )
        }

        // カスタムキー
        for customKey in customStore.keys {
            allKeys.append(APIKey(
                customKey: customKey,
                isConfigured: keychainService.exists(for: customKey.envVarName)
            ))
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
