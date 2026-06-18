import Foundation
import Observation

@Observable
final class KeyEditorViewModel {
    var selectedService: ServiceType?
    var envVarName: String = ""
    var tokenValue: String = ""
    var showToken: Bool = false
    var isSaving: Bool = false
    var showSaveSuccess: Bool = false
    var showDeleteConfirm: Bool = false
    var errorMessage: String?
    var selectedCategorySelection: CategorySelection?

    let editingKey: APIKey?
    private let keychainService: KeychainServiceProtocol
    private let customStore: CustomKeyStore

    var isEditing: Bool { editingKey != nil }

    var title: String {
        isEditing ? "Edit Key" : "Add Key"
    }

    var prefixWarning: String? {
        guard !tokenValue.isEmpty,
              let prefix = selectedService?.tokenPrefix,
              !tokenValue.hasPrefix(prefix) else {
            return nil
        }
        return "Expected prefix: \(prefix)"
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
            selectedService = key.service ?? .anthropic
            envVarName = key.envVarName

            // Resolve current category
            if let builtinCat = key.builtinCategory {
                selectedCategorySelection = .builtin(builtinCat)
            } else if let customId = key.customCategoryId {
                selectedCategorySelection = .custom(customId)
            }

            tokenValue = (try? keychainService.retrieve(for: key.envVarName)) ?? ""
        } else {
            // 新規: 未選択状態で開始
            selectedService = nil
            envVarName = ""
            selectedCategorySelection = nil
        }
    }

    func onServiceChange() {
        if !isEditing, let service = selectedService {
            envVarName = service.envVarName
            selectedCategorySelection = .builtin(service.category)
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

            if let key = editingKey {
                // 既存キーの編集
                if let service = key.service {
                    customStore.setCategoryOverride(
                        envVarName: trimmedEnvVar,
                        value: categoryOverrideValue(defaultCategory: service.category))
                } else if let customKey = key.customKey {
                    // カスタムキーのカテゴリ変更
                    var updated = customKey
                    updated.categoryId = resolveCategoryId()
                    customStore.updateKey(updated)
                }
            } else {
                // 新規キー
                if let preset = ServiceType.allCases.first(where: { $0.envVarName == trimmedEnvVar }) {
                    // envVarName がプリセットに一致 → プリセットキーとして一覧表示される。
                    // 選択カテゴリがプリセット既定と異なる場合のみカテゴリ上書きを保存する
                    // （Service 未選択でカテゴリだけ変えたケースを取りこぼさない / #102）。
                    customStore.setCategoryOverride(
                        envVarName: trimmedEnvVar,
                        value: categoryOverrideValue(defaultCategory: preset.category))
                } else {
                    let customKey = CustomKey(
                        envVarName: trimmedEnvVar,
                        displayName: selectedService?.displayName ?? trimmedEnvVar,
                        categoryId: resolveCategoryId(),
                        tokenPrefix: selectedService?.tokenPrefix,
                        setupURLString: selectedService?.setupURL?.absoluteString
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
        // カテゴリ上書きも削除
        customStore.setCategoryOverride(envVarName: key.envVarName, value: nil)
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
