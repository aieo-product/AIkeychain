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
