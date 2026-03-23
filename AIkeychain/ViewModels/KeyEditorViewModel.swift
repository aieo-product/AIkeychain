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
            selectedService = key.service
            envVarName = key.envVarName
            // Load existing value
            tokenValue = (try? keychainService.retrieve(for: key.envVarName)) ?? ""
        } else {
            selectedService = .anthropic
            envVarName = ServiceType.anthropic.envVarName
        }
    }

    func onServiceChange() {
        if !isEditing {
            envVarName = selectedService.envVarName
        }
    }

    func save() throws {
        let trimmedValue = tokenValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return }

        isSaving = true
        errorMessage = nil

        do {
            try keychainService.save(value: trimmedValue, for: envVarName)
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
    }
}
