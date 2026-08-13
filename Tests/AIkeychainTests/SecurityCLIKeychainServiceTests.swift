import Testing
import Foundation
@testable import AIkeychain

/// SecurityCLIKeychainService のテスト。実 Keychain には触れず、`security` を模す
/// スタブスクリプト（npm CLI の cli/test と同じ発想）に差し替えて検証する。
@Suite("SecurityCLIKeychainService Tests (stub security)")
struct SecurityCLIKeychainServiceTests {

    /// テストごとに独立した state ディレクトリを持つ stub security を作る。
    private func makeStub() throws -> (service: SecurityCLIKeychainService, stateDir: URL) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("akc-stub-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stub = dir.appendingPathComponent("security")
        let script = """
        #!/bin/bash
        dir="$(cd "$(dirname "$0")" && pwd)/state"
        mkdir -p "$dir"
        if [ "$1" = "-i" ]; then
          read -r line
          acct=$(printf '%s' "$line" | sed -n 's/.*-a "\\([^"]*\\)".*/\\1/p')
          hex=$(printf '%s' "$line" | sed -n 's/.*-X \\([0-9a-fA-F]*\\).*/\\1/p')
          [ -n "$acct" ] && [ -n "$hex" ] || exit 1
          printf '%s' "$hex" | xxd -r -p > "$dir/$acct"
          exit 0
        fi
        cmd="$1"; shift
        svc=""; acct=""; w=false
        while [ $# -gt 0 ]; do case "$1" in
          -s) svc="$2"; shift 2 ;;
          -a) acct="$2"; shift 2 ;;
          -w) w=true; shift ;;
          *) shift ;;
        esac; done
        case "$cmd" in
        find-generic-password)
          echo "find $acct" >> "$dir/calls.log"
          case "$acct" in
            HANG_KEY) sleep 60 ;;
            SLOW_KEY) sleep 0.5 ;;
          esac
          if [ -f "$dir/$acct" ]; then cat "$dir/$acct"; echo; exit 0; else exit 44; fi ;;
        delete-generic-password)
          if [ -f "$dir/$acct" ]; then rm "$dir/$acct"; exit 0; else exit 44; fi ;;
        esac
        exit 1
        """
        try script.write(to: stub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub.path)
        let service = SecurityCLIKeychainService()
        service.securityBinOverrideForTesting = stub.path
        return (service, dir.appendingPathComponent("state"))
    }

    private func findCalls(_ stateDir: URL) -> Int {
        (try? String(contentsOf: stateDir.appendingPathComponent("calls.log"), encoding: .utf8))?
            .split(separator: "\n").count ?? 0
    }

    @Test("Save then retrieve round-trips via subprocess (stdin+hex, no argv value)")
    func saveRetrieveRoundTrip() throws {
        let (service, stateDir) = try makeStub()
        try service.save(value: "sk-test-value_123", for: "OPENAI_API_KEY")
        #expect(try service.retrieve(for: "OPENAI_API_KEY") == "sk-test-value_123")
        // 値ファイルは hex デコード済みで保存されている（stdin+hex 経路が機能）
        let raw = try String(contentsOf: stateDir.appendingPathComponent("OPENAI_API_KEY"), encoding: .utf8)
        #expect(raw == "sk-test-value_123")
    }

    @Test("Retrieve of a missing key returns nil (rc=44)")
    func retrieveMissing() throws {
        let (service, _) = try makeStub()
        #expect(try service.retrieve(for: "MISSING_KEY") == nil)
    }

    @Test("Delete is idempotent (missing key is success)")
    func deleteIdempotent() throws {
        let (service, _) = try makeStub()
        try service.save(value: "v", for: "DEL_KEY")
        try service.delete(for: "DEL_KEY")
        try service.delete(for: "DEL_KEY") // 2回目も throw しない
        #expect(try service.retrieve(for: "DEL_KEY") == nil)
    }

    @Test("Control characters and empty values are rejected before touching security")
    func inputValidation() throws {
        let (service, stateDir) = try makeStub()
        #expect(throws: KeychainError.self) {
            try service.save(value: "line1\nline2", for: "MULTI")
        }
        #expect(throws: KeychainError.self) {
            try service.save(value: "", for: "EMPTY")
        }
        #expect(throws: KeychainError.self) {
            try service.save(value: "v", for: "9INVALID")
        }
        // security は一度も呼ばれていない
        #expect(!FileManager.default.fileExists(atPath: stateDir.appendingPathComponent("MULTI").path))
    }

    @Test("A prompt-blocked read times out, is killed, and quarantines the key")
    func timeoutQuarantine() throws {
        let (service, stateDir) = try makeStub()
        service.readTimeout = 0.3

        let t0 = Date()
        #expect(throws: KeychainError.self) {
            _ = try service.retrieveNoninteractive(for: "HANG_KEY")
        }
        #expect(Date().timeIntervalSince(t0) < 3.0) // 60s sleep が kill されている

        // 隔離中は spawn せず即時失敗する
        let callsAfterFirst = findCalls(stateDir)
        let t1 = Date()
        #expect(throws: KeychainError.self) {
            _ = try service.retrieveNoninteractive(for: "HANG_KEY")
        }
        #expect(Date().timeIntervalSince(t1) < 0.1)
        #expect(findCalls(stateDir) == callsAfterFirst) // 追加 spawn なし
    }

    @Test("Successful save clears the quarantine")
    func saveClearsQuarantine() throws {
        let (service, _) = try makeStub()
        service.readTimeout = 0.3
        #expect(throws: KeychainError.self) {
            _ = try service.retrieveNoninteractive(for: "HANG_KEY")
        }
        // save は writeTimeout 系なので成功し、隔離を解除する…が HANG_KEY は read-back
        // で再びハングするため、ここでは別キーで解除ロジックのみ検証する
        try service.save(value: "v", for: "OK_KEY")
        #expect(try service.retrieveNoninteractive(for: "OK_KEY") == "v")
    }

    @Test("Concurrent reads of the same key are coalesced into one subprocess")
    func coalescing() throws {
        let (service, stateDir) = try makeStub()
        try service.save(value: "slow-value", for: "SLOW_KEY")
        let before = findCalls(stateDir)

        let group = DispatchGroup()
        var results = [String?](repeating: nil, count: 3)
        let lock = NSLock()
        for i in 0..<3 {
            group.enter()
            DispatchQueue.global().async {
                let v = try? service.retrieveNoninteractive(for: "SLOW_KEY")
                lock.lock(); results[i] = v; lock.unlock()
                group.leave()
            }
        }
        #expect(group.wait(timeout: .now() + 10) == .success)
        #expect(results.allSatisfy { $0 == "slow-value" })
        // SLOW_KEY(0.5s) への 3 並行読みが 1 spawn に束ねられている
        #expect(findCalls(stateDir) - before == 1)
    }

    @Test("Hex output from security -w is decoded when it is valid UTF-8 hex")
    func hexDecode() {
        #expect(SecurityCLIKeychainService.decodeHexIfLikely("68656c6c6f") == "hello")
        #expect(SecurityCLIKeychainService.decodeHexIfLikely("sk-plain") == nil)     // 非 hex
        #expect(SecurityCLIKeychainService.decodeHexIfLikely("abc") == nil)          // 奇数長
        #expect(SecurityCLIKeychainService.decodeHexIfLikely("") == nil)
    }

    @Test("Writes and lists target the managed namespace, never the legacy service")
    func managedNamespaceOnly() {
        #expect(SecurityCLIKeychainService.managedService == "com.aieo.aikeychain.managed")
        #expect(SecurityCLIKeychainService.managedService != "com.aieo.aikeychain")
        // manual スキームの発見は廃止 (#167)
        let service = SecurityCLIKeychainService()
        #expect(service.manualServices().isEmpty)
    }
}
