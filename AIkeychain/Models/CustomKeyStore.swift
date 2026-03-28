import Foundation
import SwiftUI

/// ユーザー定義のカスタムカテゴリ
struct CustomCategory: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var systemImage: String
    var colorHex: UInt

    var color: Color { Color(hex: colorHex) }

    init(id: UUID = UUID(), name: String, systemImage: String = "folder", colorHex: UInt = 0x6B7280) {
        self.id = id
        self.name = name
        self.systemImage = systemImage
        self.colorHex = colorHex
    }
}

/// ユーザー定義のカスタムキー
struct CustomKey: Identifiable, Codable, Hashable {
    var id: UUID
    var envVarName: String
    var displayName: String
    var categoryId: UUID  // CustomCategory.id or built-in category ID
    var tokenPrefix: String?
    var setupURLString: String?

    var setupURL: URL? {
        setupURLString.flatMap { URL(string: $0) }
    }

    init(id: UUID = UUID(), envVarName: String, displayName: String, categoryId: UUID, tokenPrefix: String? = nil, setupURLString: String? = nil) {
        self.id = id
        self.envVarName = envVarName
        self.displayName = displayName
        self.categoryId = categoryId
        self.tokenPrefix = tokenPrefix
        self.setupURLString = setupURLString
    }
}

/// カスタムキー・カテゴリの永続化ストア
@Observable
final class CustomKeyStore {
    static let shared = CustomKeyStore()

    private static let categoriesKey = "custom_categories"
    private static let keysKey = "custom_keys"
    private static let overridesKey = "category_overrides"

    var categories: [CustomCategory] = []
    var keys: [CustomKey] = []
    /// プリセットキーのカテゴリ上書き（envVarName → カテゴリ識別子）
    var categoryOverrides: [String: String] = [:]

    private init() {
        load()
    }

    // MARK: - Categories

    func addCategory(_ category: CustomCategory) {
        categories.append(category)
        saveCategories()
    }

    func updateCategory(_ category: CustomCategory) {
        if let idx = categories.firstIndex(where: { $0.id == category.id }) {
            categories[idx] = category
            saveCategories()
        }
    }

    func deleteCategory(_ id: UUID) {
        categories.removeAll { $0.id == id }
        // カテゴリに属するキーも削除
        keys.removeAll { $0.categoryId == id }
        saveCategories()
        saveKeys()
    }

    func category(for id: UUID) -> CustomCategory? {
        categories.first { $0.id == id }
    }

    // MARK: - Keys

    func addKey(_ key: CustomKey) {
        keys.append(key)
        saveKeys()
    }

    func updateKey(_ key: CustomKey) {
        if let idx = keys.firstIndex(where: { $0.id == key.id }) {
            keys[idx] = key
            saveKeys()
        }
    }

    func deleteKey(_ id: UUID) {
        keys.removeAll { $0.id == id }
        saveKeys()
    }

    // MARK: - Category Overrides (for preset keys)

    /// プリセットキーのカテゴリを上書き
    /// value: "builtin:カテゴリrawValue" or "custom:カテゴリUUID"
    func setCategoryOverride(envVarName: String, value: String?) {
        if let value {
            categoryOverrides[envVarName] = value
        } else {
            categoryOverrides.removeValue(forKey: envVarName)
        }
        saveOverrides()
    }

    /// プリセットキーの上書きカテゴリを取得
    func overriddenCategory(for envVarName: String) -> CategorySelection? {
        guard let raw = categoryOverrides[envVarName] else { return nil }
        if raw.hasPrefix("builtin:") {
            let name = String(raw.dropFirst(8))
            if let cat = KeyCategory.allCases.first(where: { $0.rawValue == name }) {
                return .builtin(cat)
            }
        } else if raw.hasPrefix("custom:") {
            let uuidStr = String(raw.dropFirst(7))
            if let uuid = UUID(uuidString: uuidStr) {
                return .custom(uuid)
            }
        }
        return nil
    }

    // MARK: - Persistence

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Self.categoriesKey),
           let decoded = try? JSONDecoder().decode([CustomCategory].self, from: data) {
            categories = decoded
        }
        if let data = UserDefaults.standard.data(forKey: Self.keysKey),
           let decoded = try? JSONDecoder().decode([CustomKey].self, from: data) {
            keys = decoded
        }
        if let dict = UserDefaults.standard.dictionary(forKey: Self.overridesKey) as? [String: String] {
            categoryOverrides = dict
        }
    }

    private func saveCategories() {
        if let data = try? JSONEncoder().encode(categories) {
            UserDefaults.standard.set(data, forKey: Self.categoriesKey)
        }
    }

    private func saveKeys() {
        if let data = try? JSONEncoder().encode(keys) {
            UserDefaults.standard.set(data, forKey: Self.keysKey)
        }
    }

    private func saveOverrides() {
        UserDefaults.standard.set(categoryOverrides, forKey: Self.overridesKey)
    }
}
