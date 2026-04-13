import Foundation

/// プロキシの環境変数設定を管理する
///
/// 設計思想: プロキシ起動時に設定ファイルを生成し、停止時に削除する。
/// .zshrc には `[ -f ~/.aikeychain_proxy ] && source ~/.aikeychain_proxy` の
/// 1行だけ追加してもらう。ファイルが存在しない = プロキシ未稼働 → BASE_URL 未設定。
/// これにより「プロキシが動いていないのに BASE_URL が残る」問題を構造的に防止する。
enum SetupManager {

    /// プロキシ起動中のみ存在する設定ファイル
    static let proxyEnvPath = NSHomeDirectory() + "/.aikeychain_proxy"

    /// .zshrc に追記するフック
    /// ファイルが存在し、かつプロキシポートが実際に応答する場合のみ source する。
    /// 強制シャットダウン等でファイルが残っても、プロキシ未稼働なら読み込まれない。
    /// また、残ったファイルを自動削除する（次回起動時にクリーンな状態になる）。
    private static let zshrcSourceLine = """
    if [ -f ~/.aikeychain_proxy ]; then
      _aikp=$(grep -om1 'localhost:[0-9]*' ~/.aikeychain_proxy | head -1 | cut -d: -f2)
      if [ -n "$_aikp" ] && (echo >/dev/tcp/127.0.0.1/$_aikp) 2>/dev/null; then
        source ~/.aikeychain_proxy
      else
        rm -f ~/.aikeychain_proxy
      fi
      unset _aikp
    fi
    """

    private static var zshrcPath: String {
        NSHomeDirectory() + "/.zshrc"
    }

    // MARK: - Proxy Env File (起動/停止で自動管理)

    /// プロキシ起動時に設定ファイルを生成
    static func activateProxy(port: UInt16) throws {
        let content = """
        # AI KeyChain Proxy — this file is auto-managed
        # Deleted when proxy stops. Do not edit manually.
        export ANTHROPIC_BASE_URL=http://localhost:\(port)
        export OPENAI_BASE_URL=http://localhost:\(port)
        export XAI_BASE_URL=http://localhost:\(port)
        """
        try content.write(toFile: proxyEnvPath, atomically: true, encoding: .utf8)
    }

    /// プロキシ停止時に設定ファイルを削除
    static func deactivateProxy() {
        try? FileManager.default.removeItem(atPath: proxyEnvPath)
    }

    /// プロキシ設定ファイルが存在するか
    static func isProxyActive() -> Bool {
        FileManager.default.fileExists(atPath: proxyEnvPath)
    }

    // MARK: - .zshrc Hook (ユーザーが1回だけ実行)

    /// .zshrc に source 行が設定済みか確認
    static func isConfigured() -> Bool {
        guard let content = try? String(contentsOfFile: zshrcPath, encoding: .utf8) else {
            return false
        }
        return content.contains(".aikeychain_proxy")
    }

    /// .zshrc にフックを追記
    static func configure() throws {
        guard !isConfigured() else { return }

        var content = (try? String(contentsOfFile: zshrcPath, encoding: .utf8)) ?? ""

        if !content.isEmpty && !content.hasSuffix("\n") {
            content += "\n"
        }

        content += "\n# AI KeyChain — proxy env is auto-managed (exists only while proxy runs)\n"
        content += zshrcSourceLine
        content += "\n"

        try content.write(toFile: zshrcPath, atomically: true, encoding: .utf8)
    }

    // MARK: - .zshrc Export Line Management

    /// .zshrc から指定した環境変数名の export 行を削除
    /// バックアップを作成してから編集する
    static func removeExportLines(envVarNames: [String]) throws {
        guard !envVarNames.isEmpty else { return }

        let content = try String(contentsOfFile: zshrcPath, encoding: .utf8)

        // バックアップ
        let backupPath = zshrcPath + ".aikeychain.bak"
        try content.write(toFile: backupPath, atomically: true, encoding: .utf8)

        let lines = content.components(separatedBy: "\n")
        let filtered = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // export VAR_NAME= で始まる行を削除
            for name in envVarNames {
                if trimmed.hasPrefix("export \(name)=") || trimmed.hasPrefix("export \(name) =") {
                    return false
                }
            }
            return true
        }

        var result = filtered.joined(separator: "\n")

        // 連続する空行を整理
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        try result.write(toFile: zshrcPath, atomically: true, encoding: .utf8)
    }

    /// macOS Keychain (システム) から指定キーの値を読み取る
    /// security find-generic-password で保存された値を取得
    static func readSystemKeychainValue(for account: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", account, "-a", NSUserName(), "-w"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    /// .zshrc から source 行を削除
    static func unconfigure() throws {
        guard isConfigured() else { return }

        var content = try String(contentsOfFile: zshrcPath, encoding: .utf8)

        // source 行とコメント行を削除
        let lines = content.components(separatedBy: "\n")
        let filtered = lines.filter { line in
            !line.contains(".aikeychain_proxy") &&
            !line.contains("AI KeyChain — proxy env")
        }
        content = filtered.joined(separator: "\n")

        // 連続する空行を整理
        while content.contains("\n\n\n") {
            content = content.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        try content.write(toFile: zshrcPath, atomically: true, encoding: .utf8)
    }
}
