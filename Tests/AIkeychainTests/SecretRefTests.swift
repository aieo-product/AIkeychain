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

    @Test("Standard format emits the managed lookup (v2.0 #188)")
    func standardManagedScheme() {
        // v2.0: 全キーは managed namespace。厳密一致の lookup を出す（`||` fallback
        // や -a "$USER" は使わない）。
        let keys = [makeKey(service: .github)]
        let output = ZshrcExporter.export(keys: keys, format: .zshrc)
        #expect(output.contains("# [AI KeyChain]"))
        #expect(output.contains(
            "export GITHUB_TOKEN=$(/usr/bin/security find-generic-password -s \"com.aieo.aikeychain.managed\" -a \"GITHUB_TOKEN\" -w)"
        ))
        #expect(!output.contains("-s \"com.aieo.aikeychain\" -a \"GITHUB_TOKEN\"")) // legacy service は出さない
        #expect(!output.contains("-a \"$USER\""))
        #expect(!output.contains("||"))
    }

    @Test("Standard format uses absolute security path")
    func standardSecurityPath() {
        let keys = [
            makeKey(service: .github),
            makeKey(service: .openAI),
        ]
        let output = ZshrcExporter.export(keys: keys, format: .zshrc)
        let lookupLines = output.split(separator: "\n").filter {
            $0.contains("find-generic-password")
        }
        #expect(!lookupLines.isEmpty)
        #expect(lookupLines.allSatisfy {
            $0.contains("$(/usr/bin/security find-generic-password")
        })
        #expect(output.contains("$(/usr/bin/security find-generic-password"))
        #expect(!output.contains("$(security "))
        #expect(!output.contains("$( security"))
    }

    @Test("Env format includes service name comments")
    func envComments() {
        let keys = [makeKey(service: .openAI)]
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
            makeKey(service: .openAI),
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
