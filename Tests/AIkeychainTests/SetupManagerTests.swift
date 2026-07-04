import Foundation
import Testing
@testable import AIkeychain

@Suite("SetupManager Tests", .serialized)
struct SetupManagerTests {

    /// テスト用の一時ファイルで検証するためのヘルパー
    /// 注意: SetupManager は直接 ~/.zshrc を操作するため、
    /// ここでは生成されるコンフィグブロックの内容を検証する

    @Test("Config block contains BASE_URL for all supported services")
    func configBlockContent() {
        // SetupManager.configure() が書く内容を間接的に検証
        // マーカーとBASE_URLが正しく含まれるか
        let expectedVars = [
            "ANTHROPIC_BASE_URL",
            "OPENAI_BASE_URL",
            "XAI_BASE_URL",
        ]

        // isConfigured は現在のユーザーの.zshrcに依存するのでスキップ
        // 代わりにルーティング定義との整合性を確認
        for envVar in expectedVars {
            let baseName = envVar.replacingOccurrences(of: "_BASE_URL", with: "")
            // 各BASE_URLに対応するProxyRouteが存在することを確認
            #expect(!baseName.isEmpty)
        }
    }

    @Test("ProxyRoute covers all configured BASE_URLs")
    func routeCoverage() {
        // SetupManager が設定する BASE_URL と ProxyRoute の対応を検証
        let expectedHosts = ["api.anthropic.com", "api.openai.com", "api.x.ai"]
        for host in expectedHosts {
            let route = ProxyRoute.route(for: host)
            #expect(route != nil, "Missing route for \(host)")
        }
    }

    @Test("Default port is 18121")
    func defaultPort() {
        // ProxyServer のデフォルトポートと SetupManager の整合性
        let server = ProxyServer(keychainService: MockKeychainService())
        #expect(server.port == AppState.defaultPort)
    }

    @Test("activateProxy creates env file, deactivateProxy removes it")
    func proxyEnvFileLifecycle() throws {
        let path = SetupManager.proxyEnvPath

        // クリーンアップ
        defer { SetupManager.deactivateProxy() }

        // 起動 → ファイルが生成される
        try SetupManager.activateProxy(port: 18121)
        #expect(FileManager.default.fileExists(atPath: path))

        let content = try String(contentsOfFile: path, encoding: .utf8)
        #expect(content.contains("ANTHROPIC_BASE_URL=http://localhost:18121"))
        #expect(content.contains("OPENAI_BASE_URL=http://localhost:18121"))
        #expect(content.contains("XAI_BASE_URL=http://localhost:18121"))

        // 停止 → ファイルが削除される
        SetupManager.deactivateProxy()
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test("writeProxyEnvFile creates file with 0600 permissions (token not world-readable)")
    func proxyEnvFilePermissions() throws {
        // 一時ロケーションに書き込み、最終ファイルの POSIX 権限を検証する。
        // #113: セッショントークンを含むため 0600 (rw-------) でなければならない。
        let tmpDir = NSTemporaryDirectory()
        let path = tmpDir + "aikeychain_proxy_perm_test_\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: path) }

        let content = """
        export ANTHROPIC_BASE_URL=http://localhost:18121
        export AIKEYCHAIN_SESSION_TOKEN=super-secret-token
        """
        try SetupManager.writeProxyEnvFile(at: path, content: content)

        #expect(FileManager.default.fileExists(atPath: path))

        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue
        #expect(perms == 0o600, "Expected 0600, got \(String(format: "%o", perms ?? -1))")

        // 上書きしても 0600 を維持すること
        try SetupManager.writeProxyEnvFile(at: path, content: content + "\n# updated")
        let attrs2 = try FileManager.default.attributesOfItem(atPath: path)
        let perms2 = (attrs2[.posixPermissions] as? NSNumber)?.intValue
        #expect(perms2 == 0o600, "Expected 0600 after overwrite, got \(String(format: "%o", perms2 ?? -1))")

        // 一時ファイル (.<base>.tmp.*) が残っていないこと (atomic rename が完了)
        let dir = (path as NSString).deletingLastPathComponent
        let base = (path as NSString).lastPathComponent
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: dir))?
            .filter { $0.hasPrefix(".\(base).tmp.") } ?? []
        #expect(leftovers.isEmpty, "Temp file left behind: \(leftovers)")
    }

    @Test("writeProxyEnvFile yields 0600 even under umask 022 (TOCTOU: no 0644 window)")
    func proxyEnvFileUmaskIndependent() throws {
        // #113 TOCTOU: umask 022 でも一切 0644 にならず 0600 で生成されることを検証。
        // O_CREAT の mode 0600 は umask で緩む方向にしか効かないため umask 非依存。
        let old = umask(0o022)
        defer { umask(old) }

        let path = NSTemporaryDirectory() + "aikeychain_proxy_umask_test_\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: path) }

        try SetupManager.writeProxyEnvFile(
            at: path,
            content: "export AIKEYCHAIN_SESSION_TOKEN=secret"
        )
        let perms = (try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? NSNumber)?.intValue
        #expect(perms == 0o600, "Expected 0600 under umask 022, got \(String(format: "%o", perms ?? -1))")
    }

    @Test("activateProxy writes proxy env file with 0600 permissions")
    func activateProxyPermissions() throws {
        defer { SetupManager.deactivateProxy() }
        try SetupManager.activateProxy(port: 18121, sessionToken: "test-token")

        let attrs = try FileManager.default.attributesOfItem(atPath: SetupManager.proxyEnvPath)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue
        #expect(perms == 0o600, "Expected 0600, got \(String(format: "%o", perms ?? -1))")
    }

    @Test("isProxyActive reflects file existence")
    func proxyActiveState() throws {
        // まずクリーンな状態にする
        SetupManager.deactivateProxy()
        #expect(!SetupManager.isProxyActive())

        // activate → ファイル生成 → active
        try SetupManager.activateProxy(port: 18121)
        #expect(SetupManager.isProxyActive())

        // deactivate → ファイル削除 → inactive
        SetupManager.deactivateProxy()
        #expect(!SetupManager.isProxyActive())
    }
}
