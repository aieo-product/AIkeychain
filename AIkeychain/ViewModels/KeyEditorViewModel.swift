import Foundation
import Observation

@Observable
final class KeyEditorViewModel {
    var selectedService: ServiceType = .anthropic
    var envVarName: String = ""
    var tokenValue: String = ""
    var showToken: Bool = false
    var isSaving: Bool = false
    var showSaveSuccess: Bool = false
    var showDeleteConfirm: Bool = false
    var errorMessage: String?
    var selectedCategorySelection: CategorySelection = .builtin(.ai)

    let editingKey: APIKey?
    private let keychainService: KeychainServiceProtocol

    var isEditing: Bool { editingKey != nil }

    var title: String {
        isEditing ? "Edit Key" : "Add Key"
    }

    var prefixWarning: String? {
        guard !tokenValue.isEmpty,
              let prefix = selectedService.tokenPrefix,
              !tokenValue.hasPrefix(prefix) else {
            return nil
        }
        return "Expected prefix: \(prefix)"
    }

    var canSave: Bool {
        !tokenValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !envVarName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(editingKey: APIKey? = nil, keychainService: KeychainServiceProtocol = KeychainService.shared) {
        self.editingKey = editingKey
        self.keychainService = keychainService

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
            selectedService = .anthropic
            envVarName = ServiceType.anthropic.envVarName
            selectedCategorySelection = .builtin(.ai)
        }
    }

    func onServiceChange() {
        if !isEditing {
            envVarName = selectedService.envVarName
            selectedCategorySelection = .builtin(selectedService.category)
        }
    }

    func save() throws {
        let trimmedValue = tokenValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return }

        isSaving = true
        errorMessage = nil

        do {
            try keychainService.save(value: trimmedValue, for: envVarName)

            // Save category override if different from default
            if let key = editingKey, key.service != nil {
                let defaultCategory = key.service!.category
                let overrideValue: String? = {
                    switch selectedCategorySelection {
                    case .builtin(let cat) where cat == defaultCategory:
                        return nil  // デフォルトに戻す → 上書き削除
                    case .builtin(let cat):
                        return "builtin:\(cat.rawValue)"
                    case .custom(let id):
                        return "custom:\(id.uuidString)"
                    case .all, .activity:
                        return nil
                    }
                }()
                CustomKeyStore.shared.setCategoryOverride(envVarName: envVarName, value: overrideValue)
            } else if let customKey = editingKey?.customKey {
                // カスタムキーのカテゴリ変更
                if case .custom(let id) = selectedCategorySelection {
                    var updated = customKey
                    updated.categoryId = id
                    CustomKeyStore.shared.updateKey(updated)
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
        CustomKeyStore.shared.setCategoryOverride(envVarName: key.envVarName, value: nil)
    }
}
