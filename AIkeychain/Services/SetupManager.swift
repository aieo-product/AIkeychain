import Foundation

/// .zshrc のプロキシ設定を自動管理する
/// API キーの値は一切書き込まず、BASE_URL のみ設定する
enum SetupManager {

    private static let markerStart = "# --- AI KeyChain Proxy Configuration ---"
    private static let markerEnd = "# --- End AI KeyChain ---"

    private static var zshrcPath: String {
        NSHomeDirectory() + "/.zshrc"
    }

    /// プロキシ設定が .zshrc に既にあるか確認
    static func isConfigured() -> Bool {
        guard let content = try? String(contentsOfFile: zshrcPath, encoding: .utf8) else {
            return false
        }
        return content.contains(markerStart)
    }

    /// .zshrc にプロキシ設定を追記
    /// API キーは書き込まない — BASE_URL のみ
    static func configure(port: UInt16 = 9999) throws {
        let configBlock = generateConfigBlock(port: port)

        if isConfigured() {
            // 既存設定を更新
            try replaceExistingConfig(with: configBlock)
        } else {
            // 新規追記
            try appendConfig(configBlock)
        }
    }

    /// .zshrc からプロキシ設定を削除
    static func unconfigure() throws {
        guard isConfigured() else { return }

        var content = try String(contentsOfFile: zshrcPath, encoding: .utf8)

        // マーカー間を削除
        if let startRange = content.range(of: markerStart),
           let endRange = content.range(of: markerEnd) {
            // マーカー行含む前後の改行も削除
            let removeStart = content[..<startRange.lowerBound].lastIndex(of: "\n") ?? startRange.lowerBound
            let removeEnd = endRange.upperBound
            content.removeSubrange(removeStart..<removeEnd)
        }

        try content.write(toFile: zshrcPath, atomically: true, encoding: .utf8)
    }

    // MARK: - Private

    private static func generateConfigBlock(port: UInt16) -> String {
        """
        \(markerStart)
        # API keys are securely injected by AIkeychain proxy (never stored in env)
        # Proxy reads from macOS Keychain on each request
        export ANTHROPIC_BASE_URL=http://localhost:\(port)
        export OPENAI_BASE_URL=http://localhost:\(port)
        export XAI_BASE_URL=http://localhost:\(port)
        \(markerEnd)
        """
    }

    private static func replaceExistingConfig(with newBlock: String) throws {
        var content = try String(contentsOfFile: zshrcPath, encoding: .utf8)

        if let startRange = content.range(of: markerStart),
           let endRange = content.range(of: markerEnd) {
            content.replaceSubrange(startRange.lowerBound...endRange.upperBound, with: newBlock)
        }

        try content.write(toFile: zshrcPath, atomically: true, encoding: .utf8)
    }

    private static func appendConfig(_ block: String) throws {
        // バックアップ作成
        let backupPath = zshrcPath + ".aikeychain.bak"
        if FileManager.default.fileExists(atPath: zshrcPath) {
            try? FileManager.default.copyItem(atPath: zshrcPath, toPath: backupPath)
        }

        var content = (try? String(contentsOfFile: zshrcPath, encoding: .utf8)) ?? ""

        // 末尾に改行がなければ追加
        if !content.isEmpty && !content.hasSuffix("\n") {
            content += "\n"
        }

        content += "\n" + block + "\n"

        try content.write(toFile: zshrcPath, atomically: true, encoding: .utf8)
    }
}
