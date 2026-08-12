import Testing
@testable import AIkeychain

@Suite("MockKeychainService Tests")
struct KeychainServiceTests {

    @Test("Save and retrieve a key")
    func saveAndRetrieve() throws {
        let service = MockKeychainService()
        try service.save(value: "sk-ant-test123", for: "ANTHROPIC_API_KEY")

        let result = try service.retrieve(for: "ANTHROPIC_API_KEY")
        #expect(result == "sk-ant-test123")
    }

    @Test("Retrieve non-existent key returns nil")
    func retrieveNonExistent() throws {
        let service = MockKeychainService()
        let result = try service.retrieve(for: "NON_EXISTENT")
        #expect(result == nil)
    }

    @Test("Exists returns true for saved key")
    func existsTrue() throws {
        let service = MockKeychainService()
        try service.save(value: "value", for: "KEY")
        #expect(service.exists(for: "KEY") == true)
    }

    @Test("Exists returns false for missing key")
    func existsFalse() {
        let service = MockKeychainService()
        #expect(service.exists(for: "KEY") == false)
    }

    @Test("Delete removes key")
    func deleteKey() throws {
        let service = MockKeychainService()
        try service.save(value: "value", for: "KEY")
        try service.delete(for: "KEY")
        #expect(service.exists(for: "KEY") == false)
    }

    @Test("Save overwrites existing value")
    func saveOverwrite() throws {
        let service = MockKeychainService()
        try service.save(value: "old", for: "KEY")
        try service.save(value: "new", for: "KEY")
        let result = try service.retrieve(for: "KEY")
        #expect(result == "new")
    }

    // MARK: - #177: 毒化防止（fail-closed）

    @Test("Editing a CLI/security-owned key fails closed instead of poisoning (#177)")
    func securityOwnedEditFailsClosed() throws {
        let service = MockKeychainService()
        // `akc set` 等で作られ security 所有になっているキーを模す。
        service.store["OPENAI_API_KEY"] = "sk-original"
        service.securityOwnedAccounts.insert("OPENAI_API_KEY")

        #expect(throws: KeychainError.self) {
            try service.save(value: "sk-overwritten", for: "OPENAI_API_KEY")
        }
        // 値は未変更（in-process 編集による毒化が起きない）
        #expect(service.store["OPENAI_API_KEY"] == "sk-original")
    }

    @Test("cliManaged error tells the user to use `akc set <KEY>` (#177)")
    func cliManagedErrorMessage() {
        let message = KeychainError.cliManaged("OPENAI_API_KEY").errorDescription ?? ""
        #expect(message.contains("akc set OPENAI_API_KEY"))
    }

    @Test("A brand-new key and a GUI-owned key still save normally (#177 no regression)")
    func newAndGuiOwnedStillSave() throws {
        let service = MockKeychainService()
        // 新規
        try service.save(value: "v1", for: "GITHUB_TOKEN")
        #expect(try service.retrieve(for: "GITHUB_TOKEN") == "v1")
        // GUI 所有（securityOwned でない）→ 上書き可
        try service.save(value: "v2", for: "GITHUB_TOKEN")
        #expect(try service.retrieve(for: "GITHUB_TOKEN") == "v2")
    }
}
