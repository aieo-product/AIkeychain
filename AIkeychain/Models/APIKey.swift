import Foundation
import SwiftUI

/// キー値が Keychain のどちらのスキームに保存されているか (#160)。
/// .app    = service=com.aieo.aikeychain, account=<キー名>（GUI / akc set 新規）
/// .manual = service=<キー名>（`security add-generic-password -s KEY` の手動登録）
/// 両スキームに存在する場合は 2 段ルックアップの優先順に従い .app とする。
enum StorageScheme {
    case app
    case manual
}

struct APIKey: Identifiable, Equatable, Hashable {
    static func == (lhs: APIKey, rhs: APIKey) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    let id: UUID
    let service: ServiceType?        // プリセットの場合
    let customKey: CustomKey?        // カスタムの場合
    var envVarName: String
    var isConfigured: Bool
    var storage: StorageScheme

    /// プリセットキー
    init(id: UUID = UUID(), service: ServiceType, envVarName: String? = nil, isConfigured: Bool = false,
         storage: StorageScheme = .app) {
        self.id = id
        self.service = service
        self.customKey = nil
        self.envVarName = envVarName ?? service.envVarName
        self.isConfigured = isConfigured
        self.storage = storage
    }

    /// カスタムキー
    init(id: UUID = UUID(), customKey: CustomKey, isConfigured: Bool = false,
         storage: StorageScheme = .app) {
        self.id = id
        self.service = nil
        self.customKey = customKey
        self.envVarName = customKey.envVarName
        self.isConfigured = isConfigured
        self.storage = storage
    }

    var isCustom: Bool { customKey != nil }

    var displayName: String {
        service?.displayName ?? customKey?.displayName ?? envVarName
    }

    var systemImage: String {
        // 1. ユーザーがこのキーに設定した個別アイコンを最優先
        if let customKey, let icon = customKey.icon, !icon.isEmpty {
            return icon
        }
        if let override = CustomKeyStore.shared.overriddenIcon(for: envVarName), !override.isEmpty {
            return override
        }
        // 2. プリセット名キーを別カテゴリへ移している場合は、その実効カテゴリのアイコン
        //    （エディタの既定選択と一致させ「nil はカテゴリ追従」を成立させる）
        if let sel = CustomKeyStore.shared.overriddenCategory(for: envVarName),
           let icon = Self.categoryIcon(for: sel), !icon.isEmpty {
            return icon
        }
        // 3. プリセット由来のアイコン（既定配置のプリセット名キー）
        if let service { return service.systemImage }
        // 4. カスタムキーが属するカテゴリのアイコン
        if let customKey, let cat = CustomKeyStore.shared.category(for: customKey.categoryId),
           !cat.systemImage.isEmpty {
            return cat.systemImage
        }
        // 5. ビルトインカテゴリのアイコン（プリセット名キーのフォールバック）
        if let builtin = builtinCategory, !builtin.systemImage.isEmpty { return builtin.systemImage }
        return "key"
    }

    private static func categoryIcon(for selection: CategorySelection) -> String? {
        switch selection {
        case .builtin(let cat): return cat.systemImage
        case .custom(let id): return CustomKeyStore.shared.category(for: id)?.systemImage
        case .all, .activity: return nil
        }
    }

    var categoryColor: Color {
        // 表示中カテゴリ（override 込みの実効値）から色を解決する。合成キーの元 categoryId
        // ではなく customCategoryId / builtinCategory を使うことで、発見キーをカスタム/別ビルトイン
        // カテゴリへ移しても色が gray に落ちない（#153 / Codex #2・#3）。
        if let customId = customCategoryId, let cat = CustomKeyStore.shared.category(for: customId) {
            return cat.color
        }
        if let builtin = builtinCategory { return builtin.color }
        if let service { return service.category.color }
        return .gray
    }

    /// プリセットの KeyCategory か、カスタムカテゴリの ID
    /// カテゴリ上書きが設定されている場合はそちらを優先
    var builtinCategory: KeyCategory? {
        if let override = CustomKeyStore.shared.overriddenCategory(for: envVarName) {
            if case .builtin(let cat) = override { return cat }
            return nil  // カスタムカテゴリに上書きされた場合
        }
        if let service { return service.category }
        // カスタムキーが stableId でビルトインカテゴリを参照している場合
        if let customKey { return KeyCategory.from(stableId: customKey.categoryId) }
        return nil
    }

    var customCategoryId: UUID? {
        if let override = CustomKeyStore.shared.overriddenCategory(for: envVarName) {
            if case .custom(let id) = override { return id }
            return nil  // ビルトインカテゴリに上書きされた場合
        }
        if let customKey {
            // stableId がビルトインカテゴリに該当する場合は nil
            if KeyCategory.from(stableId: customKey.categoryId) != nil { return nil }
            return customKey.categoryId
        }
        return nil
    }

    var setupURL: URL? {
        service?.setupURL ?? customKey?.setupURL
    }

    var tokenPrefix: String? {
        service?.tokenPrefix ?? customKey?.tokenPrefix
    }
}
