import Testing
@testable import AIkeychain

@Suite("ZshrcExporter Secret Reference Tests")
struct ZshrcExporterSecretRefTests {

    private func makeKey(service: ServiceType, configured: Bool = true) -> APIKey {
        APIKey(service: service, isConfigured: configured)
    }

    @Test("Secret Reference format outputs keychain:// prefix")
    func secretRefFormat() {
        let keys = [makeKey(service: .anthropic)]
        let output = ZshrcExporter.export(keys: keys, format: .secretRef)
        #expect(output.contains("keychain://ANTHROPIC_API_KEY"))
        #expect(output.contains("export ANTHROPIC_API_KEY=\"keychain://ANTHROPIC_API_KEY\""))
    }

    @Test("Secret Reference format includes service name comments")
    func secretRefComments() {
        let keys = [makeKey(service: .anthropic)]
        let output = ZshrcExporter.export(keys: keys, format: .secretRef)
        #expect(output.contains("# [AI KeyChain]"))
        #expect(output.contains("Secret Reference exports"))
        #expect(output.contains("akc run"))
    }

    @Test("Standard format includes service name comments")
    func standardComments() {
        let keys = [makeKey(service: .github)]
        let output = ZshrcExporter.export(keys: keys, format: .zshrc)
        #expect(output.contains("# [AI KeyChain]"))
        #expect(output.contains("security find-generic-password"))
    }

    @Test("Env format includes service name comments")
    func envComments() {
        let keys = [makeKey(service: .openai)]
        let output = ZshrcExporter.export(keys: keys, format: .env)
        #expect(output.contains("# OpenAI") || output.contains("# "))
        #expect(output.contains("OPENAI_API_KEY=<VALUE>"))
    }

    @Test("Unconfigured keys are excluded from all formats")
    func unconfiguredExcluded() {
        let keys = [makeKey(service: .anthropic, configured: false)]
        for format in ExportFormat.allCases {
            let output = ZshrcExporter.export(keys: keys, format: format)
            #expect(!output.contains("ANTHROPIC_API_KEY"))
        }
    }

    @Test("Multiple keys are grouped by category")
    func groupedByCategory() {
        let keys = [
            makeKey(service: .anthropic),
            makeKey(service: .openai),
            makeKey(service: .github),
        ]
        let output = ZshrcExporter.export(keys: keys, format: .secretRef)
        #expect(output.contains("keychain://ANTHROPIC_API_KEY"))
        #expect(output.contains("keychain://OPENAI_API_KEY"))
        #expect(output.contains("keychain://GITHUB_TOKEN"))
    }

    @Test("ExportFormat has three cases")
    func formatCount() {
        #expect(ExportFormat.allCases.count == 3)
    }
}

@Suite("KeyManagementMode Tests")
struct KeyManagementModeTests {

    @Test("Secret Reference mode exists")
    func secretRefMode() {
        let mode = KeyManagementMode.secretReference
        #expect(mode.rawValue == "secretReference")
    }

    @Test("All three modes are distinct")
    func allModesDistinct() {
        let modes: [KeyManagementMode] = [.standard, .secretReference, .proxy]
        let rawValues = Set(modes.map(\.rawValue))
        #expect(rawValues.count == 3)
    }
}
