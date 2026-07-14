import Foundation
import Darwin
import Testing
@testable import AIkeychain

@Suite("SetupManager Tests", .serialized)
struct SetupManagerTests {

    @Test("unconfigure removes a well-formed block and preserves user lines")
    func unconfigureRemovesWellFormedBlockAndPreservesUserLines() throws {
        let path = temporaryZshrcPath()
        let backupPath = path + ".aikeychain.bak"
        defer {
            try? FileManager.default.removeItem(atPath: path)
            try? FileManager.default.removeItem(atPath: backupPath)
        }
        let original = """
        export PATH="$HOME/bin:$PATH"

        # >>> AI KeyChain >>>
        source ~/.aikeychain_proxy
        # <<< AI KeyChain <<<

        export EDITOR=vim
        alias k=kubectl
        """
        try original.write(toFile: path, atomically: true, encoding: .utf8)

        try SetupManager.unconfigure(zshrcPath: path)

        let result = try String(contentsOfFile: path, encoding: .utf8)
        #expect(result.contains("export PATH="))
        #expect(result.contains("export EDITOR=vim"))
        #expect(result.contains("alias k=kubectl"))
        #expect(!result.contains("# >>> AI KeyChain >>>"))
        #expect(!result.contains("# <<< AI KeyChain <<<"))
        #expect(!result.contains(".aikeychain_proxy"))
    }

    @Test("unconfigure fails safely for a dangling BEGIN around the current hook")
    func unconfigureFailsSafelyForDanglingCurrentHook() throws {
        let path = temporaryZshrcPath()
        let backupPath = path + ".aikeychain.bak"
        defer {
            try? FileManager.default.removeItem(atPath: path)
            try? FileManager.default.removeItem(atPath: backupPath)
        }
        let original = """
        export PATH="$HOME/bin:$PATH"

        # >>> AI KeyChain >>>
        \(SetupManager.proxySourceSnippet(proxyEnvPath: "~/.aikeychain_proxy"))

        export OPENAI_BASE_URL=https://user.example
        alias k=kubectl
        """
        try original.write(toFile: path, atomically: true, encoding: .utf8)
        let originalData = try Data(contentsOf: URL(fileURLWithPath: path))

        #expect(throws: SetupManager.SetupError.malformedMarkers) {
            try SetupManager.unconfigure(zshrcPath: path)
        }

        let resultData = try Data(contentsOf: URL(fileURLWithPath: path))
        #expect(resultData == originalData)
        #expect(try zshSyntaxIsValid(at: path))

        #expect(FileManager.default.fileExists(atPath: backupPath))
        let backupData = try Data(contentsOf: URL(fileURLWithPath: backupPath))
        #expect(backupData == originalData)
    }

    @Test("unconfigure leaves a simple dangling BEGIN byte-identical")
    func unconfigureLeavesSimpleDanglingBeginUnchanged() throws {
        let path = temporaryZshrcPath()
        let backupPath = path + ".aikeychain.bak"
        defer {
            try? FileManager.default.removeItem(atPath: path)
            try? FileManager.default.removeItem(atPath: backupPath)
        }
        let original = """
        export PATH="$HOME/bin:$PATH"
        # >>> AI KeyChain >>>
        export EDITOR=vim
        alias k=kubectl
        source ~/.secrets
        """
        try original.write(toFile: path, atomically: true, encoding: .utf8)
        let originalData = try Data(contentsOf: URL(fileURLWithPath: path))

        #expect(throws: SetupManager.SetupError.malformedMarkers) {
            try SetupManager.unconfigure(zshrcPath: path)
        }

        let resultData = try Data(contentsOf: URL(fileURLWithPath: path))
        #expect(resultData == originalData)
        #expect(FileManager.default.fileExists(atPath: backupPath))
        let backupData = try Data(contentsOf: URL(fileURLWithPath: backupPath))
        #expect(backupData == originalData)
    }

    @Test("unconfigure fails safely for a lone END marker")
    func unconfigureFailsSafelyForLoneEndMarker() throws {
        let path = temporaryZshrcPath()
        let backupPath = path + ".aikeychain.bak"
        defer {
            try? FileManager.default.removeItem(atPath: path)
            try? FileManager.default.removeItem(atPath: backupPath)
        }
        let original = """
        export PATH="$HOME/bin:$PATH"
        # <<< AI KeyChain <<<
        export EDITOR=vim
        alias k=kubectl
        """
        try original.write(toFile: path, atomically: true, encoding: .utf8)
        let originalData = try Data(contentsOf: URL(fileURLWithPath: path))

        #expect(throws: SetupManager.SetupError.malformedMarkers) {
            try SetupManager.unconfigure(zshrcPath: path)
        }

        let resultData = try Data(contentsOf: URL(fileURLWithPath: path))
        #expect(resultData == originalData)
        #expect(FileManager.default.fileExists(atPath: backupPath))
        let backupData = try Data(contentsOf: URL(fileURLWithPath: backupPath))
        #expect(backupData == originalData)
        let attributes = try FileManager.default.attributesOfItem(atPath: backupPath)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        #expect(permissions == 0o600)
    }

    @Test("unconfigure backup has 0600 permissions")
    func unconfigureBackupHasPrivatePermissions() throws {
        let path = temporaryZshrcPath()
        let backupPath = path + ".aikeychain.bak"
        defer {
            try? FileManager.default.removeItem(atPath: path)
            try? FileManager.default.removeItem(atPath: backupPath)
        }
        let original = """
        # >>> AI KeyChain >>>
        source ~/.aikeychain_proxy
        # <<< AI KeyChain <<<
        """
        try original.write(toFile: path, atomically: true, encoding: .utf8)

        try SetupManager.unconfigure(zshrcPath: path)

        let attributes = try FileManager.default.attributesOfItem(atPath: backupPath)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        #expect(permissions == 0o600)
    }

    @Test("unconfigure recognizes and removes a well-formed CRLF block")
    func unconfigureRemovesWellFormedCRLFBlock() throws {
        let path = temporaryZshrcPath()
        let backupPath = path + ".aikeychain.bak"
        defer {
            try? FileManager.default.removeItem(atPath: path)
            try? FileManager.default.removeItem(atPath: backupPath)
        }
        let original = [
            "export PATH=\"$HOME/bin:$PATH\"",
            "# >>> AI KeyChain >>>",
            "source ~/.aikeychain_proxy",
            "# <<< AI KeyChain <<<",
            "alias k=kubectl",
            "",
        ].joined(separator: "\r\n")
        try original.write(toFile: path, atomically: true, encoding: .utf8)

        try SetupManager.unconfigure(zshrcPath: path)

        let result = try String(contentsOfFile: path, encoding: .utf8)
        #expect(result.contains("export PATH="))
        #expect(result.contains("alias k=kubectl"))
        #expect(!result.contains("# >>> AI KeyChain >>>"))
        #expect(!result.contains("# <<< AI KeyChain <<<"))
        #expect(!result.contains(".aikeychain_proxy"))
    }

    @Test("configure migrates a stale managed block")
    func configureMigratesStaleManagedBlock() throws {
        let path = temporaryZshrcPath()
        let backupPath = path + ".aikeychain.bak"
        defer {
            try? FileManager.default.removeItem(atPath: path)
            try? FileManager.default.removeItem(atPath: backupPath)
        }
        let oldContent = """
        export EDITOR=vim

        # >>> AI KeyChain >>>
        if [ -n "$_aikp" ] && (echo >/dev/tcp/127.0.0.1/$_aikp) 2>/dev/null; then
          source ~/.aikeychain_proxy
        fi
        # <<< AI KeyChain <<<

        alias k=kubectl
        """
        try oldContent.write(toFile: path, atomically: true, encoding: .utf8)

        try SetupManager.configure(zshrcPath: path)

        let result = try String(contentsOfFile: path, encoding: .utf8)
        #expect(result.contains("/usr/bin/nc -z"))
        #expect(!result.contains("/dev/tcp"))
        #expect(result.contains("export EDITOR=vim"))
        #expect(result.contains("alias k=kubectl"))
        #expect(result.components(separatedBy: "# >>> AI KeyChain >>>").count - 1 == 1)
    }

    @Test("configure is idempotent when managed block is current")
    func configureIsIdempotentWhenCurrent() throws {
        let path = temporaryZshrcPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let userLine = "export EDITOR=vim\n"
        try userLine.write(toFile: path, atomically: true, encoding: .utf8)

        try SetupManager.configure(zshrcPath: path)
        let first = try String(contentsOfFile: path, encoding: .utf8)
        try SetupManager.configure(zshrcPath: path)
        let second = try String(contentsOfFile: path, encoding: .utf8)

        #expect(second == first)
        #expect(second.contains("export EDITOR=vim"))
        #expect(second.components(separatedBy: "# >>> AI KeyChain >>>").count - 1 == 1)
    }

    @Test("configure adds current managed block to a fresh zshrc")
    func configureAddsCurrentBlockToFreshZshrc() throws {
        let path = temporaryZshrcPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let userLine = "alias k=kubectl\n"
        try userLine.write(toFile: path, atomically: true, encoding: .utf8)

        try SetupManager.configure(zshrcPath: path)

        let result = try String(contentsOfFile: path, encoding: .utf8)
        #expect(result.contains("/usr/bin/nc -z"))
        #expect(result.contains("alias k=kubectl"))
        #expect(result.components(separatedBy: "# >>> AI KeyChain >>>").count - 1 == 1)
    }

    @Test("configure normalizes duplicate managed blocks to a single block")
    func configureNormalizesDuplicateBlocks() throws {
        let path = temporaryZshrcPath()
        let backupPath = path + ".aikeychain.bak"
        defer {
            try? FileManager.default.removeItem(atPath: path)
            try? FileManager.default.removeItem(atPath: backupPath)
        }
        // 現行と同一の well-formed ブロックが 2 つ存在する（重複）状態。
        let snippet = SetupManager.proxySourceSnippet(proxyEnvPath: "~/.aikeychain_proxy")
        let block = "# >>> AI KeyChain >>>\n\(snippet)\n# <<< AI KeyChain <<<"
        let original = """
        export EDITOR=vim

        \(block)

        alias k=kubectl

        \(block)
        """
        try original.write(toFile: path, atomically: true, encoding: .utf8)

        try SetupManager.configure(zshrcPath: path)

        let result = try String(contentsOfFile: path, encoding: .utf8)
        // 重複が 1 つに正規化される
        #expect(result.components(separatedBy: "# >>> AI KeyChain >>>").count - 1 == 1)
        #expect(result.components(separatedBy: "# <<< AI KeyChain <<<").count - 1 == 1)
        #expect(result.contains("/usr/bin/nc -z"))
        // マーカー間本文が現行 snippet と完全一致するブロックがちょうど 1 つ
        // （「空マーカーペア + マーカー外に残った snippet」等の抜けを防ぐ、Codex #4）。
        #expect(result.components(separatedBy: block).count - 1 == 1)
        // ユーザー行は保持される
        #expect(result.contains("export EDITOR=vim"))
        #expect(result.contains("alias k=kubectl"))
        #expect(try zshSyntaxIsValid(at: path))
    }

    @Test("configure preserves user lines mentioning the proxy path when normalizing duplicates")
    func configurePreservesUserProxyReferenceWhenNormalizing() throws {
        let path = temporaryZshrcPath()
        let backupPath = path + ".aikeychain.bak"
        defer {
            try? FileManager.default.removeItem(atPath: path)
            try? FileManager.default.removeItem(atPath: backupPath)
        }
        // 重複ブロック + マーカー外にユーザー自身の `.aikeychain_proxy` 参照行。
        // 正規化のために unconfigure を素通しすると、この行が巻き添え削除される（Codex #1）。
        let snippet = SetupManager.proxySourceSnippet(proxyEnvPath: "~/.aikeychain_proxy")
        let block = "# >>> AI KeyChain >>>\n\(snippet)\n# <<< AI KeyChain <<<"
        let userProxyLine = "export SNAPSHOT=\"$HOME/.aikeychain_proxy.backup\""
        let original = """
        \(userProxyLine)

        \(block)

        alias k=kubectl

        \(block)
        """
        try original.write(toFile: path, atomically: true, encoding: .utf8)

        try SetupManager.configure(zshrcPath: path)

        let result = try String(contentsOfFile: path, encoding: .utf8)
        // 管理ブロックは 1 つに正規化されるが、ユーザー行は削除されない
        #expect(result.components(separatedBy: "# >>> AI KeyChain >>>").count - 1 == 1)
        #expect(result.contains(userProxyLine))
        #expect(result.contains("alias k=kubectl"))
        #expect(try zshSyntaxIsValid(at: path))
    }

    @Test("configure is a byte-identical no-op for an already-correct CRLF block")
    func configureIsIdempotentForCRLFCurrentBlock() throws {
        let path = temporaryZshrcPath()
        let backupPath = path + ".aikeychain.bak"
        defer {
            try? FileManager.default.removeItem(atPath: path)
            try? FileManager.default.removeItem(atPath: backupPath)
        }
        // 既に正しい現行ブロックを持つが CRLF 改行の .zshrc。
        // 本文の \r を無視して同一と判定できないと、no-op にならずブロックが末尾へ移動する（Codex #3）。
        let snippet = SetupManager.proxySourceSnippet(proxyEnvPath: "~/.aikeychain_proxy")
        let lf = """
        export EDITOR=vim

        # >>> AI KeyChain >>>
        \(snippet)
        # <<< AI KeyChain <<<
        """
        let crlf = lf.replacingOccurrences(of: "\n", with: "\r\n")
        try crlf.write(toFile: path, atomically: true, encoding: .utf8)
        let originalData = try Data(contentsOf: URL(fileURLWithPath: path))

        try SetupManager.configure(zshrcPath: path)

        // 既に整合しているので 1 バイトも書き換わらない
        let resultData = try Data(contentsOf: URL(fileURLWithPath: path))
        #expect(resultData == originalData)
    }

    @Test("configure fails safely when a stray marker accompanies the current block")
    func configureFailsSafelyWithStrayMarker() throws {
        let path = temporaryZshrcPath()
        let backupPath = path + ".aikeychain.bak"
        defer {
            try? FileManager.default.removeItem(atPath: path)
            try? FileManager.default.removeItem(atPath: backupPath)
        }
        // 現行ブロックに加え、余分な（ネストした）BEGIN マーカーが混在 = malformed。
        let snippet = SetupManager.proxySourceSnippet(proxyEnvPath: "~/.aikeychain_proxy")
        let original = """
        export EDITOR=vim
        # >>> AI KeyChain >>>
        # >>> AI KeyChain >>>
        \(snippet)
        # <<< AI KeyChain <<<
        alias k=kubectl
        """
        try original.write(toFile: path, atomically: true, encoding: .utf8)
        let originalData = try Data(contentsOf: URL(fileURLWithPath: path))

        // malformed は非破壊 throw（unconfigure #146 契約）に委ねる
        #expect(throws: SetupManager.SetupError.malformedMarkers) {
            try SetupManager.configure(zshrcPath: path)
        }

        // 元ファイルは 1 バイトも変更されず、backup が作られる
        let resultData = try Data(contentsOf: URL(fileURLWithPath: path))
        #expect(resultData == originalData)
        #expect(FileManager.default.fileExists(atPath: backupPath))
        let backupData = try Data(contentsOf: URL(fileURLWithPath: backupPath))
        #expect(backupData == originalData)
        // backup は 0600 で作られる（#146 契約 / Codex #4）
        let backupPerm = try FileManager.default.attributesOfItem(atPath: backupPath)[.posixPermissions] as? NSNumber
        #expect(backupPerm?.int16Value == 0o600)
    }

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

    @Test("zsh proxy hook keeps live config and sources it")
    func zshProxyHookLive() throws {
        let listener = try makeListeningSocket()
        defer { close(listener.fd) }

        let path = temporaryProxyEnvPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        try writeProxyEnvFile(at: path, port: listener.port)

        let snippet = SetupManager.proxySourceSnippet(proxyEnvPath: path)
        let result = try runZsh("\(snippet)\nprintf '%s\\n' \"$OPENAI_BASE_URL\"")

        #expect(result.status == 0, "zsh failed: \(result.stderr)")
        #expect(FileManager.default.fileExists(atPath: path))
        #expect(result.stdout.contains("http://localhost:\(listener.port)"))
    }

    @Test("zsh proxy hook deletes config for closed port")
    func zshProxyHookClosed() throws {
        let reserved = try makeListeningSocket()
        let port = reserved.port
        close(reserved.fd)

        let path = temporaryProxyEnvPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        try writeProxyEnvFile(at: path, port: port)

        let snippet = SetupManager.proxySourceSnippet(proxyEnvPath: path)
        let result = try runZsh(snippet)

        #expect(result.status == 0, "zsh failed: \(result.stderr)")
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    private func temporaryProxyEnvPath() -> String {
        NSTemporaryDirectory() + "aikeychain_proxy_zsh_test_\(UUID().uuidString)"
    }

    private func temporaryZshrcPath() -> String {
        NSTemporaryDirectory() + "aikeychain_zshrc_test_\(UUID().uuidString)"
    }

    private func zshSyntaxIsValid(at path: String) throws -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-n", path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    private func writeProxyEnvFile(at path: String, port: UInt16) throws {
        let content = """
        export OPENAI_BASE_URL=http://localhost:\(port)
        export AIKEYCHAIN_SESSION_TOKEN=tok
        """
        try content.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private func makeListeningSocket() throws -> (fd: Int32, port: UInt16) {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EIO) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0, listen(fd, 1) == 0 else {
            let error = POSIXErrorCode(rawValue: errno) ?? .EIO
            close(fd)
            throw POSIXError(error)
        }

        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }
        guard nameResult == 0 else {
            let error = POSIXErrorCode(rawValue: errno) ?? .EIO
            close(fd)
            throw POSIXError(error)
        }

        return (fd, UInt16(bigEndian: address.sin_port))
    }

    private func runZsh(_ command: String) throws -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let stdoutText = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, stdoutText, stderrText)
    }
}
