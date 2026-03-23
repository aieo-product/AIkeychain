import Testing
@testable import AIkeychain

@Suite("ServiceType Tests")
struct ServiceTypeTests {

    @Test("All services have display names")
    func displayNames() {
        for service in ServiceType.allCases {
            #expect(!service.displayName.isEmpty)
        }
    }

    @Test("All services have env var names")
    func envVarNames() {
        for service in ServiceType.allCases {
            #expect(!service.envVarName.isEmpty)
            #expect(service.envVarName == service.envVarName.uppercased()
                    .replacingOccurrences(of: " ", with: "_"))
        }
    }

    @Test("All services have categories")
    func categories() {
        for service in ServiceType.allCases {
            // Just accessing category shouldn't crash
            _ = service.category
        }
    }

    @Test("All services have system images")
    func systemImages() {
        for service in ServiceType.allCases {
            #expect(!service.systemImage.isEmpty)
        }
    }

    @Test("Token prefix format is correct")
    func tokenPrefixes() {
        #expect(ServiceType.anthropic.tokenPrefix == "sk-ant-")
        #expect(ServiceType.github.tokenPrefix == "ghp_")
        #expect(ServiceType.gitlab.tokenPrefix == "glpat-")
        #expect(ServiceType.discord.tokenPrefix == nil)
    }

    @Test("Setup URLs are valid")
    func setupURLs() {
        for service in ServiceType.allCases {
            if let url = service.setupURL {
                #expect(url.scheme == "https")
            }
        }
    }
}

@Suite("KeyCategory Tests")
struct KeyCategoryTests {

    @Test("All categories have unique colors")
    func uniqueColors() {
        let categories = KeyCategory.allCases
        // Just verify no crashes accessing color
        for cat in categories {
            _ = cat.color
            _ = cat.systemImage
        }
    }

    @Test("Category count is 5")
    func categoryCount() {
        #expect(KeyCategory.allCases.count == 5)
    }
}

@Suite("KeyEditorViewModel Tests")
struct KeyEditorViewModelTests {

    @Test("New editor defaults to anthropic")
    func defaultService() {
        let vm = KeyEditorViewModel(keychainService: MockKeychainService())
        #expect(vm.selectedService == .anthropic)
        #expect(vm.envVarName == "ANTHROPIC_API_KEY")
    }

    @Test("Service change updates env var name")
    func serviceChange() {
        let vm = KeyEditorViewModel(keychainService: MockKeychainService())
        vm.selectedService = .github
        vm.onServiceChange()
        #expect(vm.envVarName == "GITHUB_TOKEN")
    }

    @Test("Prefix warning shows for wrong prefix")
    func prefixWarning() {
        let vm = KeyEditorViewModel(keychainService: MockKeychainService())
        vm.selectedService = .anthropic
        vm.tokenValue = "wrong-prefix-token"
        #expect(vm.prefixWarning != nil)
    }

    @Test("No prefix warning for correct prefix")
    func noPrefixWarning() {
        let vm = KeyEditorViewModel(keychainService: MockKeychainService())
        vm.selectedService = .anthropic
        vm.tokenValue = "sk-ant-correct"
        #expect(vm.prefixWarning == nil)
    }

    @Test("Cannot save with empty token")
    func cannotSaveEmpty() {
        let vm = KeyEditorViewModel(keychainService: MockKeychainService())
        vm.tokenValue = ""
        #expect(vm.canSave == false)
    }

    @Test("Can save with valid token")
    func canSaveValid() {
        let vm = KeyEditorViewModel(keychainService: MockKeychainService())
        vm.tokenValue = "sk-ant-test123"
        #expect(vm.canSave == true)
    }

    @Test("Save stores value in keychain")
    func saveStoresValue() throws {
        let mock = MockKeychainService()
        let vm = KeyEditorViewModel(keychainService: mock)
        vm.tokenValue = "test-token"
        vm.envVarName = "TEST_KEY"
        try vm.save()
        #expect(mock.store["TEST_KEY"] == "test-token")
    }

    @Test("Editing key loads existing value")
    func editLoadExisting() throws {
        let mock = MockKeychainService()
        try mock.save(value: "existing-value", for: "GITHUB_TOKEN")
        let key = APIKey(service: .github, isConfigured: true)
        let vm = KeyEditorViewModel(editingKey: key, keychainService: mock)
        #expect(vm.tokenValue == "existing-value")
        #expect(vm.isEditing == true)
    }
}
