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

}
