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
    static func proxySourceSnippet(proxyEnvPath: String) -> String {
        """
    if [ -f \(proxyEnvPath) ]; then
      _aikp=$(grep -om1 'localhost:[0-9]*' \(proxyEnvPath) | head -1 | cut -d: -f2)
      if [ -n "$_aikp" ] && /usr/bin/nc -z -G 1 127.0.0.1 "$_aikp" >/dev/null 2>&1; then
        source \(proxyEnvPath)
      else
        rm -f \(proxyEnvPath)
      fi
      unset _aikp
    fi
    """
    }

    private static let zshrcSourceLine = proxySourceSnippet(proxyEnvPath: "~/.aikeychain_proxy")

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

    enum SetupError: LocalizedError, Equatable {
        case malformedMarkers

        var errorDescription: String? {
            switch self {
            case .malformedMarkers:
                return "AI KeyChain の .zshrc マーカー構造が壊れています。ファイルは変更せず、バックアップを作成しました。"
            }
        }
    }

    /// .zshrc に AI KeyChain ブロックが設定済みか確認
    static func isConfigured() -> Bool {
        isConfigured(zshrcPath: zshrcPath)
    }

    static func isConfigured(zshrcPath: String) -> Bool {
        guard let content = try? String(contentsOfFile: zshrcPath, encoding: .utf8) else {
            return false
        }
        return content.contains(markerBegin) || content.contains(".aikeychain_proxy")
    }

    /// レガシー形式かどうか（マーカーなしの旧バージョン）
    private static func hasLegacyFormat(zshrcPath: String) -> Bool {
        guard let content = try? String(contentsOfFile: zshrcPath, encoding: .utf8) else { return false }
        return content.contains(".aikeychain_proxy") && !content.contains(markerBegin)
    }

    /// マーカー構造の解析結果
    private struct MarkerAnalysis {
        /// BEGIN/END がネストなく過不足なく対応しているか（unconfigure と同一判定）
        let isWellFormed: Bool
        /// 各ブロックの BEGIN/END 間の内容（各行を "\n" で join、末尾改行なし）
        let blockContents: [String]
    }

    /// .zshrc の内容から AI KeyChain マーカーブロックの構造を解析する。
    /// well-formedness の判定は unconfigure(zshrcPath:) と同一ロジックに揃える
    /// （isWellFormed == true ならその後 unconfigure が throw しないことを保証する）。
    private static func analyzeMarkers(in content: String) -> MarkerAnalysis {
        let lines = content.components(separatedBy: "\n")
        var isWellFormed = true
        var blocks: [String] = []
        var current: [String] = []
        var inBlock = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == markerBegin {
                if inBlock { isWellFormed = false }   // ネストした BEGIN
                inBlock = true
                current = []
            } else if trimmed == markerEnd {
                if !inBlock {
                    isWellFormed = false              // 対応する BEGIN のない END
                } else {
                    blocks.append(current.joined(separator: "\n"))
                }
                inBlock = false
            } else if inBlock {
                current.append(line)
            }
        }
        if inBlock { isWellFormed = false }           // 閉じられていない BEGIN

        return MarkerAnalysis(isWellFormed: isWellFormed, blockContents: blocks)
    }

    /// well-formed なマーカーブロックだけを取り除き、ブロック外の行は一切変更せず残す。
    /// unconfigure と異なりレガシー行（`.aikeychain_proxy` を含む行等）の削除は行わないため、
    /// マーカー外にあるユーザー自身の設定を巻き添え削除しない（#148 / Codex #1）。
    /// 呼び出し側は事前に isWellFormed == true を保証すること（malformed は unconfigure に委ねる）。
    private static func removingMarkerBlocks(from content: String) -> String {
        let lines = content.components(separatedBy: "\n")
        var result: [String] = []
        var inBlock = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == markerBegin {
                inBlock = true
                continue
            }
            if trimmed == markerEnd {
                inBlock = false
                continue
            }
            if !inBlock {
                result.append(line)
            }
        }
        var output = result.joined(separator: "\n")
        while output.contains("\n\n\n") {
            output = output.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return output
    }

    /// .zshrc にフックを追記（BEGIN/END マーカーで囲む）
    /// レガシー形式が存在する場合は先に削除してからマーカー形式で再追加
    static func configure() throws {
        try configure(zshrcPath: zshrcPath)
    }

    static func configure(zshrcPath: String) throws {
        // レガシー形式 → マーカー形式にアップグレード
        if hasLegacyFormat(zshrcPath: zshrcPath) {
            try unconfigure(zshrcPath: zshrcPath)
        }

        let existing = (try? String(contentsOfFile: zshrcPath, encoding: .utf8)) ?? ""
        let analysis = analyzeMarkers(in: existing)

        // べき等: 構造が well-formed かつ「現行と同一のブロックがちょうど 1 つだけ」なら
        // 何もしない。CRLF 環境でも本文末尾の \r を無視して比較し、既に整合したブロックを
        // 不必要に書き換えて末尾へ移動させない（#148 / Codex #3）。
        let normalizedBlocks = analysis.blockContents.map {
            $0.replacingOccurrences(of: "\r", with: "")
        }
        if analysis.isWellFormed && normalizedBlocks == [zshrcSourceLine] {
            return
        }

        // マーカーの整理。
        // - well-formed（重複ブロック / 古い内容）→ マーカーブロックだけ除去（ブロック外の
        //   ユーザー行は保護）してから 1 つだけ再追加する。unconfigure を経由すると
        //   ブロック外の `.aikeychain_proxy` 参照行まで消えるため使わない（#148 / Codex #1）。
        // - malformed（余分/ネストしたマーカー）→ unconfigure が backup + throw（#146 契約）。
        //   analyzeMarkers と unconfigure の well-formedness 判定は同一なので必ず throw する。
        var content: String
        if analysis.isWellFormed {
            content = removingMarkerBlocks(from: existing)
        } else {
            try unconfigure(zshrcPath: zshrcPath)
            // 到達しない（malformed なので unconfigure が throw する）。防御的に中断する。
            throw SetupError.malformedMarkers
        }

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

    /// .zshrc から AI KeyChain 管理ブロック全体を削除（マーカー間 + レガシー行）。
    /// マーカー構造が壊れている場合は 0600 のバックアップだけを作り、元ファイルを変更せず throw する。
    static func unconfigure() throws {
        try unconfigure(zshrcPath: zshrcPath)
    }

    static func unconfigure(zshrcPath: String) throws {
        guard let content = try? String(contentsOfFile: zshrcPath, encoding: .utf8) else { return }
        let lines = content.components(separatedBy: "\n")
        let hasManagedMarker = lines.contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed == markerBegin || trimmed == markerEnd
        }
        let hasLegacyContent = content.contains(".aikeychain_proxy")
            || content.contains("AI KeyChain — proxy env")
        guard hasManagedMarker || hasLegacyContent else { return }

        var hasOpenBlock = false
        var markerStructureIsWellFormed = true

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == markerBegin {
                if hasOpenBlock {
                    markerStructureIsWellFormed = false
                }
                hasOpenBlock = true
            } else if trimmed == markerEnd {
                if !hasOpenBlock {
                    markerStructureIsWellFormed = false
                }
                hasOpenBlock = false
            }
        }

        if hasOpenBlock {
            markerStructureIsWellFormed = false
        }

        // 変更またはエラーを返す前に、秘密情報を含み得る元の内容を 0600 で退避する。
        let backupPath = zshrcPath + ".aikeychain.bak"
        try writeProxyEnvFile(at: backupPath, content: content)

        // 壊れたブロックを部分的に削除すると shell 構文まで破壊し得るため、元ファイルは触らない。
        guard markerStructureIsWellFormed else {
            throw SetupError.malformedMarkers
        }

        var result: [String] = []
        var inBlock = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == markerBegin {
                inBlock = true
                continue
            }
            if trimmed == markerEnd {
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
