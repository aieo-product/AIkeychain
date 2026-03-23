import Foundation

/// プロキシのルーティング定義
/// 宛先ホストごとにどの Keychain キーを使い、どのヘッダで注入するかを定義
struct ProxyRoute {
    let host: String
    let targetScheme: String
    let keychainAccount: String
    let headerName: String
    let headerValuePrefix: String // "Bearer " or ""

    /// 全ルーティングルール
    static let routes: [ProxyRoute] = [
        ProxyRoute(
            host: "api.anthropic.com",
            targetScheme: "https",
            keychainAccount: "ANTHROPIC_API_KEY",
            headerName: "x-api-key",
            headerValuePrefix: ""
        ),
        ProxyRoute(
            host: "api.openai.com",
            targetScheme: "https",
            keychainAccount: "OPENAI_API_KEY",
            headerName: "Authorization",
            headerValuePrefix: "Bearer "
        ),
        ProxyRoute(
            host: "api.x.ai",
            targetScheme: "https",
            keychainAccount: "XAI_API_KEY",
            headerName: "Authorization",
            headerValuePrefix: "Bearer "
        ),
    ]

    /// ホスト名からルートを検索
    static func route(for host: String) -> ProxyRoute? {
        routes.first { host.contains($0.host) }
    }
}
