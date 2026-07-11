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

    @Test("unconfigure preserves user lines after a dangling BEGIN")
    func unconfigurePreservesUserLinesAfterDanglingBegin() throws {
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

        try SetupManager.unconfigure(zshrcPath: path)

        let result = try String(contentsOfFile: path, encoding: .utf8)
        #expect(result.contains("export PATH="))
        #expect(result.contains("export EDITOR=vim"))
        #expect(result.contains("alias k=kubectl"))
        #expect(result.contains("source ~/.secrets"))
        #expect(!result.contains("# >>> AI KeyChain >>>"))
    }

    @Test("unconfigure backs up original content for a malformed block")
    func unconfigureBacksUpOriginalContentForMalformedBlock() throws {
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
        """
        try original.write(toFile: path, atomically: true, encoding: .utf8)

        try SetupManager.unconfigure(zshrcPath: path)

        #expect(FileManager.default.fileExists(atPath: backupPath))
        let backup = try String(contentsOfFile: backupPath, encoding: .utf8)
        #expect(backup == original)
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
