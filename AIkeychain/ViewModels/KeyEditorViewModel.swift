import Foundation
import Observation

@Observable
final class KeyEditorViewModel {
    /// 既存プリセットキーの編集時のみ参照（プレフィックス検証 / 発行 URL 表示用）。
    /// エディタにサービス選択 UI は無い。
    var selectedService: ServiceType?
    var envVarName: String = ""
    var tokenValue: String = ""
    var showToken: Bool = false
    var isSaving: Bool = false
    var showSaveSuccess: Bool = false
    var showDeleteConfirm: Bool = false
    var errorMessage: String?
    var selectedCategorySelection: CategorySelection?
    /// このキーに表示するアイコン（SF Symbol 名）。
    var selectedIcon: String = "key"
    /// ユーザーが明示的にアイコンを選んだか（カテゴリ変更で自動追従させるか判定）。
    var iconManuallySet: Bool = false

    let editingKey: APIKey?
    private let keychainService: KeychainServiceProtocol
    private let customStore: CustomKeyStore

    var isEditing: Bool { editingKey != nil }

    var title: String {
        isEditing ? L10n.s(ja: "キーを編集", en: "Edit Key") : L10n.s(ja: "キーを追加", en: "Add Key")
    }

    /// 選択中カテゴリの既定アイコン。
    var categoryDefaultIcon: String {
        switch selectedCategorySelection {
        case .builtin(let cat): return cat.systemImage
        case .custom(let id): return customStore.category(for: id)?.systemImage ?? "folder"
        case .all, .activity, .none: return "key"
        }
    }

    /// カテゴリ選択が変わったとき、ユーザー未指定なら既定アイコンに追従させる。
    func categoryDidChange() {
        if !iconManuallySet {
            selectedIcon = categoryDefaultIcon
        }
    }

    /// ユーザーがアイコンを選んだ。
    func pickIcon(_ icon: String) {
        selectedIcon = icon
        iconManuallySet = true
    }

    var prefixWarning: String? {
        guard !tokenValue.isEmpty,
              let prefix = selectedService?.tokenPrefix,
              !tokenValue.hasPrefix(prefix) else {
            return nil
        }
        return L10n.s(ja: "想定プレフィックス: \(prefix)", en: "Expected prefix: \(prefix)")
    }

    /// envVarName が安全なシェル変数名パターンに一致するか
    var isValidEnvVarName: Bool {
        let trimmed = envVarName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil
    }

    /// 保存可能条件。Service は任意のプリセット（クイック補完）に過ぎないため
    /// 必須ではない。必須は「カテゴリ + 妥当な環境変数名 + 値」。
    var canSave: Bool {
        selectedCategorySelection != nil
        && !tokenValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && isValidEnvVarName
    }

    init(editingKey: APIKey? = nil,
         keychainService: KeychainServiceProtocol = KeychainService.shared,
         customStore: CustomKeyStore = .shared) {
        self.editingKey = editingKey
        self.keychainService = keychainService
        self.customStore = customStore

        if let key = editingKey {
            selectedService = key.service
            envVarName = key.envVarName

            // Resolve current category
            if let builtinCat = key.builtinCategory {
                selectedCategorySelection = .builtin(builtinCat)
            } else if let customId = key.customCategoryId {
                selectedCategorySelection = .custom(customId)
            }

            // 明示的に保存されたアイコンがあればそれを初期値に（保存時に維持）。
            // 無ければ現在の表示アイコンを初期値にし、未指定扱い（カテゴリ追従可）。
            let explicitIcon = key.customKey?.icon ?? customStore.overriddenIcon(for: key.envVarName)
            if let explicitIcon, !explicitIcon.isEmpty {
                selectedIcon = explicitIcon
                iconManuallySet = true
            } else {
                selectedIcon = key.systemImage
                iconManuallySet = false
            }

            tokenValue = (try? keychainService.retrieve(for: key.envVarName)) ?? ""
        } else {
            // 新規: 未選択状態で開始
            selectedService = nil
            envVarName = ""
            selectedCategorySelection = nil
            selectedIcon = "key"
            iconManuallySet = false
        }
    }

    func save() throws {
        let trimmedValue = tokenValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEnvVar = envVarName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty, !trimmedEnvVar.isEmpty else { return }

        isSaving = true
        errorMessage = nil

        do {
            try keychainService.save(value: trimmedValue, for: trimmedEnvVar)

            let iconToStore = iconToPersist()

            if let key = editingKey {
                // 既存キーの編集
                if let service = key.service {
                    customStore.setCategoryOverride(
                        envVarName: trimmedEnvVar,
                        value: categoryOverrideValue(defaultCategory: service.category))
                    customStore.setIconOverride(envVarName: trimmedEnvVar, icon: iconToStore)
                } else if let customKey = key.customKey {
                    // カスタムキーのカテゴリ/アイコン変更
                    var updated = customKey
                    updated.categoryId = resolveCategoryId()
                    updated.icon = iconToStore
                    customStore.updateKey(updated)
                }
            } else {
                // 新規キー
                if let preset = ServiceType.allCases.first(where: { $0.envVarName == trimmedEnvVar }) {
                    // envVarName がプリセットに一致 → プリセットキーとして一覧表示される。
                    // 選択カテゴリ/アイコンがプリセット既定と異なる場合のみ上書きを保存
                    // （Service 未選択でカテゴリ・アイコンだけ変えたケースを取りこぼさない）。
                    customStore.setCategoryOverride(
                        envVarName: trimmedEnvVar,
                        value: categoryOverrideValue(defaultCategory: preset.category))
                    customStore.setIconOverride(envVarName: trimmedEnvVar, icon: iconToStore)
                } else {
                    let customKey = CustomKey(
                        envVarName: trimmedEnvVar,
                        displayName: trimmedEnvVar,
                        categoryId: resolveCategoryId(),
                        icon: iconToStore
                    )
                    customStore.addKey(customKey)
                }
            }

            showSaveSuccess = true
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
            throw error
        }
    }

    func deleteKey() throws {
        guard let key = editingKey else { return }
        try keychainService.delete(for: key.envVarName)
        // カテゴリ/アイコン上書きも削除
        customStore.setCategoryOverride(envVarName: key.envVarName, value: nil)
        customStore.setIconOverride(envVarName: key.envVarName, icon: nil)
    }

    // MARK: - Private

    /// 選択カテゴリをプリセット上書き文字列に変換する。
    /// プリセット既定と同じなら nil（= 上書きを保存しない/削除）。
    private func categoryOverrideValue(defaultCategory: KeyCategory) -> String? {
        switch selectedCategorySelection {
        case .builtin(let cat) where cat == defaultCategory:
            return nil
        case .builtin(let cat):
            return "builtin:\(cat.rawValue)"
        case .custom(let id):
            return "custom:\(id.uuidString)"
        case .all, .activity, .none:
            return nil
        }
    }

    /// 保存するアイコン。ユーザーが明示的に選んでいなければ nil（= カテゴリ/プリセットに
    /// 追従させ、上書きを保存しない）。明示選択時のみその値を保存する。
    private func iconToPersist() -> String? {
        guard iconManuallySet else { return nil }
        let trimmed = selectedIcon.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func resolveCategoryId() -> UUID {
        switch selectedCategorySelection {
        case .builtin(let cat):
            return cat.stableId
        case .custom(let id):
            return id
        case .all, .activity, .none:
            return KeyCategory.ai.stableId
        }
    }
}
