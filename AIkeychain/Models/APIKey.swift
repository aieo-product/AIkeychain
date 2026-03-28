import Foundation
import SwiftUI

struct APIKey: Identifiable, Equatable, Hashable {
    static func == (lhs: APIKey, rhs: APIKey) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    let id: UUID
    let service: ServiceType?        // プリセットの場合
    let customKey: CustomKey?        // カスタムの場合
    var envVarName: String
    var isConfigured: Bool

    /// プリセットキー
    init(id: UUID = UUID(), service: ServiceType, envVarName: String? = nil, isConfigured: Bool = false) {
        self.id = id
        self.service = service
        self.customKey = nil
        self.envVarName = envVarName ?? service.envVarName
        self.isConfigured = isConfigured
    }

    /// カスタムキー
    init(id: UUID = UUID(), customKey: CustomKey, isConfigured: Bool = false) {
        self.id = id
        self.service = nil
        self.customKey = customKey
        self.envVarName = customKey.envVarName
        self.isConfigured = isConfigured
    }

    var isCustom: Bool { customKey != nil }

    var displayName: String {
        service?.displayName ?? customKey?.displayName ?? envVarName
    }

    var systemImage: String {
        if let service { return service.systemImage }
        if let customKey, let cat = CustomKeyStore.shared.category(for: customKey.categoryId) {
            return cat.systemImage
        }
        return "key"
    }

    var categoryColor: Color {
        if let service { return service.category.color }
        if let customKey, let cat = CustomKeyStore.shared.category(for: customKey.categoryId) {
            return cat.color
        }
        return .gray
    }

    /// プリセットの KeyCategory か、カスタムカテゴリの ID
    /// カテゴリ上書きが設定されている場合はそちらを優先
    var builtinCategory: KeyCategory? {
        if let override = CustomKeyStore.shared.overriddenCategory(for: envVarName) {
            if case .builtin(let cat) = override { return cat }
            return nil  // カスタムカテゴリに上書きされた場合
        }
        return service?.category
    }

    var customCategoryId: UUID? {
        if let override = CustomKeyStore.shared.overriddenCategory(for: envVarName) {
            if case .custom(let id) = override { return id }
            return nil  // ビルトインカテゴリに上書きされた場合
        }
        return customKey?.categoryId
    }

    var setupURL: URL? {
        service?.setupURL ?? customKey?.setupURL
    }

    var tokenPrefix: String? {
        service?.tokenPrefix ?? customKey?.tokenPrefix
    }
}
