import Foundation
#if canImport(Darwin)
import Darwin
#endif

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
    static func activateProxy(port: UInt16, sessionToken: String = "") throws {
        var content = """
        # AI KeyChain Proxy — this file is auto-managed
        # Deleted when proxy stops. Do not edit manually.
        export ANTHROPIC_BASE_URL=http://localhost:\(port)
        export OPENAI_BASE_URL=http://localhost:\(port)
        export XAI_BASE_URL=http://localhost:\(port)
        """
        if !sessionToken.isEmpty {
            content += "\nexport AIKEYCHAIN_SESSION_TOKEN=\(sessionToken)"
        }
        try writeProxyEnvFile(at: proxyEnvPath, content: content)
    }

    /// プロキシ設定ファイルの書き込みで発生しうるエラー
    enum ProxyEnvWriteError: Error {
        case open(errno: Int32)
        case write(errno: Int32)
        case rename(errno: Int32)
        case encoding
    }

    /// プロキシ設定ファイルを 0600 (rw-------) で atomic に書き込む
    ///
    /// このファイルには `AIKEYCHAIN_SESSION_TOKEN`（ループバックプロキシの唯一の
    /// 認証情報。ユーザーの Keychain API キーで署名を行う）が含まれる。macOS では
    /// 全ローカルアカウントが group `staff` に属するため、0644 で一瞬でも公開されると
    /// co-resident 攻撃者がトークンを読み取れてしまう (#113 / TOCTOU)。
    ///
    /// 実装: 同ディレクトリ内の一時ファイルを
    /// `open(O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW, 0o600)` で作成する。mode 0600 は
    /// umask で緩む方向にしか作用しないため、**umask に依存せず確実に 0600** で生成
    /// される（0644 になる瞬間が一切存在しない）。content を書き込んでから
    /// `rename(2)` で最終パスへ atomic に差し替える。.zshrc が source するため
    /// atomic 性が必要だが、rename の前後どちらのパスにも 0600 より緩いモードの
    /// ファイルは一度も現れない。
    ///
    /// fail-closed: 途中で失敗した場合は一時ファイルを unlink し、0644 の残骸を
    /// 残さず throw する。
    static func writeProxyEnvFile(at path: String, content: String) throws {
        guard let data = content.data(using: .utf8) else {
            throw ProxyEnvWriteError.encoding
        }

        let dir = (path as NSString).deletingLastPathComponent
        let base = (path as NSString).lastPathComponent
        let tmpPath = "\(dir)/.\(base).tmp.\(getpid()).\(UInt32.random(in: 0..<UInt32.max))"

        // 一時ファイルを umask 非依存の 0600 で排他作成。シンボリックリンク攻撃も拒否。
        let fd = open(tmpPath, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        if fd < 0 {
            throw ProxyEnvWriteError.open(errno: errno)
        }

        do {
            try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                var written = 0
                let total = raw.count
                let bytes = raw.bindMemory(to: UInt8.self).baseAddress
                while written < total {
                    let n = Darwin.write(fd, bytes!.advanced(by: written), total - written)
                    if n < 0 {
                        if errno == EINTR { continue }
                        throw ProxyEnvWriteError.write(errno: errno)
                    }
                    written += n
                }
            }
        } catch {
            close(fd)
            unlink(tmpPath)   // fail-closed: 中途半端な 0600 ファイルも残さない
            throw error
        }

        close(fd)

        // atomic に最終パスへ。失敗したら一時ファイルを掃除して throw。
        if rename(tmpPath, path) != 0 {
            let err = errno
            unlink(tmpPath)
            throw ProxyEnvWriteError.rename(errno: err)
        }
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

    private static let markerBegin = "# >>> AI KeyChain >>>"
    private static let markerEnd   = "# <<< AI KeyChain <<<"

    /// .zshrc に AI KeyChain ブロックが設定済みか確認
    static func isConfigured() -> Bool {
        guard let content = try? String(contentsOfFile: zshrcPath, encoding: .utf8) else {
            return false
        }
        return content.contains(markerBegin) || content.contains(".aikeychain_proxy")
    }

    /// レガシー形式かどうか（マーカーなしの旧バージョン）
    private static var hasLegacyFormat: Bool {
        guard let content = try? String(contentsOfFile: zshrcPath, encoding: .utf8) else { return false }
        return content.contains(".aikeychain_proxy") && !content.contains(markerBegin)
    }

    /// .zshrc にフックを追記（BEGIN/END マーカーで囲む）
    /// レガシー形式が存在する場合は先に削除してからマーカー形式で再追加
    static func configure() throws {
        // レガシー形式 → マーカー形式にアップグレード
        if hasLegacyFormat {
            try unconfigure()
        }

        // マーカー形式が既に存在する場合はスキップ
        if let content = try? String(contentsOfFile: zshrcPath, encoding: .utf8),
           content.contains(markerBegin) {
            return
        }

        var content = (try? String(contentsOfFile: zshrcPath, encoding: .utf8)) ?? ""

        if !content.isEmpty && !content.hasSuffix("\n") {
            content += "\n"
        }

        content += "\n\(markerBegin)\n"
        content += zshrcSourceLine
        content += "\n\(markerEnd)\n"

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

    /// macOS Keychain (システム) から指定キーの値を読み取る。
    ///
    /// scripts/akc / npm CLI (cli/src/keychain.js) と同じ 2 段ルックアップに整合させる:
    ///   1. GUI 保存形式 `-s "com.aieo.aikeychain" -a "<KEY>"` を厳密一致で引く
    ///   2. 見つからなければ手動登録キーとして `-s "<KEY>"`（service 名のみ）で引く
    /// 手動登録キーは acct (-a) の値が一定しないため account は指定しない
    /// （acct 不整合による古い/無効な値の誤取得を防止 / issue #91）。
    static func readSystemKeychainValue(for account: String) -> String? {
        func lookup(_ arguments: [String]) -> String? {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            process.arguments = arguments

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            do {
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { return nil }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let value = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return (value?.isEmpty == false) ? value : nil
            } catch {
                return nil
            }
        }

        // 1. GUI 保存形式（service + account を厳密一致）
        if let value = lookup(["find-generic-password", "-s", "com.aieo.aikeychain", "-a", account, "-w"]) {
            return value
        }
        // 2. 手動登録キー（service 名のみ / -a は付けない）
        return lookup(["find-generic-password", "-s", account, "-w"])
    }

    /// .zshrc から AI KeyChain 管理ブロック全体を削除（マーカー間 + レガシー行）
    static func unconfigure() throws {
        guard isConfigured() else { return }

        let content = try String(contentsOfFile: zshrcPath, encoding: .utf8)
        let lines = content.components(separatedBy: "\n")

        var result: [String] = []
        var inBlock = false

        for line in lines {
            if line.trimmingCharacters(in: .whitespaces) == markerBegin {
                inBlock = true
                continue
            }
            if line.trimmingCharacters(in: .whitespaces) == markerEnd {
                inBlock = false
                continue
            }
            if !inBlock {
                // レガシー形式のフォールバック削除
                if line.contains(".aikeychain_proxy") || line.contains("AI KeyChain — proxy env") {
                    continue
                }
                result.append(line)
            }
        }

        var output = result.joined(separator: "\n")
        while output.contains("\n\n\n") {
            output = output.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        try output.write(toFile: zshrcPath, atomically: true, encoding: .utf8)
    }
}
