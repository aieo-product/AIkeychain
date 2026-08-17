import Testing
import Foundation
@testable import AIkeychain

/// SecurityCLIKeychainService のテスト。実 Keychain のアイテムには触れず、`security`
/// を模すスタブスクリプト（npm CLI の cli/test と同じ発想）と、ロック状態の
/// テストプローブ（makeStub が { false } を注入）に差し替えて検証する。
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
        # state ファイルは "state/<service>/<name>"。-s を無視すると「書き込み先
        # service が誤っていても緑」になる（#179 二段レビュー S6）ため必ず反映する。
        dir="$(cd "$(dirname "$0")" && pwd)/state"
        mkdir -p "$dir"
        if [ "$1" = "-i" ]; then
          read -r line
          svc=$(printf '%s' "$line" | sed -n 's/.*-s "\\([^"]*\\)".*/\\1/p')
          acct=$(printf '%s' "$line" | sed -n 's/.*-a "\\([^"]*\\)".*/\\1/p')
          hex=$(printf '%s' "$line" | sed -n 's/.*-X \\([0-9a-fA-F]*\\).*/\\1/p')
          [ -n "$svc" ] && [ -n "$acct" ] && [ -n "$hex" ] || exit 1
          echo "add $svc|$acct" >> "$dir/calls.log"
          mkdir -p "$dir/$svc"
          printf '%s' "$hex" | xxd -r -p > "$dir/$svc/$acct"
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
        name="${acct:-$svc}"   # manual スキーム (-a なし) は service 名で引く
        path="$dir/$svc/$name"
        case "$cmd" in
        find-generic-password)
          echo "find $svc|$name" >> "$dir/calls.log"
          case "$name" in
            HANG_KEY) [ -f "$path" ] || sleep 60 ;;  # 保存後は即応答（quarantine 解除テスト用）
            SLOW_KEY) sleep 0.5 ;;
          esac
          if [ -f "$path" ]; then cat "$path"; echo; exit 0; else exit 44; fi ;;
        delete-generic-password)
          echo "delete $svc|$name" >> "$dir/calls.log"
          if [ "$svc" = "com.aieo.aikeychain" ] && [ "$name" = "LEGACY_FAIL_KEY" ]; then
            echo denied >&2; exit 51
          fi
          if [ -f "$path" ]; then rm "$path"; exit 0; else exit 44; fi ;;
        esac
        exit 1
        """
        try script.write(to: stub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub.path)
        let service = SecurityCLIKeychainService()
        service.securityBinOverrideForTesting = stub.path
        // 実ユーザーの keychain ロック状態に依存させない（ロック中のランナーで
        // スイート全体が落ちる環境依存を防ぐ — #183 レビュー SF-1）。
        // ロック挙動のテストだけがこのプローブを上書きする。
        service.keychainLockedProbeForTesting = { false }
        return (service, dir.appendingPathComponent("state"))
    }

    private func findCalls(_ stateDir: URL) -> Int {
        callLog(stateDir).filter { $0.hasPrefix("find ") }.count
    }

    private func callLog(_ stateDir: URL) -> [String] {
        ((try? String(contentsOf: stateDir.appendingPathComponent("calls.log"), encoding: .utf8)) ?? "")
            .split(separator: "\n").map(String.init)
    }

    /// stub の state ファイルパス（service 別ディレクトリ）
    private func statePath(_ stateDir: URL, service: String, name: String) -> URL {
        stateDir.appendingPathComponent(service).appendingPathComponent(name)
    }

    /// 旧 namespace のアイテムを直接シード（旧 GUI store / manual スキームの残置を模す）
    private func seed(_ stateDir: URL, service: String, name: String, value: String = "legacy") throws {
        let dir = stateDir.appendingPathComponent(service)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try value.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    @Test("Save then retrieve round-trips via subprocess (stdin+hex, no argv value)")
    func saveRetrieveRoundTrip() throws {
        let (service, stateDir) = try makeStub()
        try service.save(value: "sk-test-value_123", for: "OPENAI_API_KEY")
        #expect(try service.retrieve(for: "OPENAI_API_KEY") == "sk-test-value_123")
        // 値ファイルは hex デコード済みで、managed namespace 配下に保存されている
        // （stdin+hex 経路 + 書き込み先 service の両方が機能 / #179 S6）
        let raw = try String(
            contentsOf: statePath(stateDir, service: SecurityCLIKeychainService.managedService,
                                  name: "OPENAI_API_KEY"),
            encoding: .utf8)
        #expect(raw == "sk-test-value_123")
        // 旧 namespace には何も書かれていない
        #expect(!FileManager.default.fileExists(
            atPath: statePath(stateDir, service: "com.aieo.aikeychain", name: "OPENAI_API_KEY").path))
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
        // 長さ上限（stdin パイプバッファ束縛 / #179 S4）
        #expect(throws: KeychainError.self) {
            try service.save(value: String(repeating: "a", count: SecurityCLIKeychainService.maxValueLength + 1),
                             for: "TOO_LONG")
        }
        // security は一度も呼ばれていない
        #expect(!FileManager.default.fileExists(
            atPath: statePath(stateDir, service: SecurityCLIKeychainService.managedService, name: "MULTI").path))
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

    @Test("Successful save clears the quarantine for that key")
    func saveClearsQuarantine() throws {
        let (service, _) = try makeStub()
        service.readTimeout = 0.3
        // 未保存の HANG_KEY はハング → timeout-kill → 隔離
        #expect(throws: KeychainError.self) {
            _ = try service.retrieveNoninteractive(for: "HANG_KEY")
        }
        // 隔離中は即時失敗する
        #expect(throws: KeychainError.self) {
            _ = try service.retrieveNoninteractive(for: "HANG_KEY")
        }
        // 保存成功（stub は保存後の HANG_KEY に即応答する）→ 隔離が解除され読める
        try service.save(value: "healed", for: "HANG_KEY")
        #expect(try service.retrieveNoninteractive(for: "HANG_KEY") == "healed")
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

    @Test("An all-hex ASCII secret round-trips verbatim (no hex-decode guessing, #179 review)")
    func allHexSecretRoundTrip() throws {
        let (service, _) = try makeStub()
        try service.save(value: "4142434445464748", for: "HEXLIKE_KEY")
        #expect(try service.retrieve(for: "HEXLIKE_KEY") == "4142434445464748")
    }

    @Test("Non-ASCII values are rejected until the C7 encoding convention lands")
    func nonAsciiRejected() throws {
        let (service, _) = try makeStub()
        #expect(throws: KeychainError.self) {
            try service.save(value: "秘密のトークン", for: "JP_KEY")
        }
    }

    @Test("Reads query only the managed namespace (issued commands, not constants)")
    func managedNamespaceOnly() throws {
        let (service, stateDir) = try makeStub()
        _ = try service.retrieve(for: "SOME_KEY")
        // 実際に発行されたコマンドの service を検証する（定数比較では書き込み先の
        // 誤りを検出できない — #179 二段レビュー S6）
        #expect(callLog(stateDir) == ["find com.aieo.aikeychain.managed|SOME_KEY"])
    }

    @Test("Delete only ever touches the managed namespace (v2.0 #188)")
    func deleteManagedOnly() throws {
        let (service, stateDir) = try makeStub()
        try service.save(value: "v1", for: "CLEAN_KEY")
        // 旧 namespace にゴミが残っていても触れない（v2.0 は legacy を読み書きしない）
        try seed(stateDir, service: "com.aieo.aikeychain", name: "CLEAN_KEY")

        try service.delete(for: "CLEAN_KEY")

        // managed の本体だけが消える
        #expect(!FileManager.default.fileExists(
            atPath: statePath(stateDir, service: SecurityCLIKeychainService.managedService, name: "CLEAN_KEY").path))
        // legacy は触られない
        #expect(FileManager.default.fileExists(
            atPath: statePath(stateDir, service: "com.aieo.aikeychain", name: "CLEAN_KEY").path))

        let deletes = callLog(stateDir).filter { $0.hasPrefix("delete ") }
        #expect(deletes == ["delete com.aieo.aikeychain.managed|CLEAN_KEY"])
    }

    @Test("A locked keychain fails fast without spawning and without quarantining (#170)")
    func lockedKeychainFailsFast() throws {
        let (service, stateDir) = try makeStub()
        var locked = true
        service.keychainLockedProbeForTesting = { locked }

        // 全エントリポイントが spawn せず、正確に interactionRequired で即時失敗する
        // （型だけの検証だと unexpectedStatus 経由の別ルートでも緑になり、Proxy の
        // 503 写像を保証できない — #183 レビュー SF-5）
        func expectInteractionRequired(_ body: () throws -> Void) {
            do { try body(); Issue.record("expected interactionRequired, nothing thrown") }
            catch KeychainError.interactionRequired {}
            catch { Issue.record("expected interactionRequired, got \(error)") }
        }
        expectInteractionRequired { try service.save(value: "v", for: "LOCK_KEY") }
        expectInteractionRequired { _ = try service.retrieve(for: "LOCK_KEY") }
        expectInteractionRequired { _ = try service.retrieveNoninteractive(for: "LOCK_KEY") }
        expectInteractionRequired { try service.delete(for: "LOCK_KEY") }
        // stub は -i（書込）も含め全コマンドを記録する — save がガードを素通りして
        // 書き込んでいれば calls.log と state ファイルに現れる
        #expect(callLog(stateDir).isEmpty)
        #expect(!FileManager.default.fileExists(
            atPath: statePath(stateDir, service: SecurityCLIKeychainService.managedService, name: "LOCK_KEY").path))

        // 解錠後は即座に使える（ロックは quarantine を残さない）
        locked = false
        try service.save(value: "v2", for: "LOCK_KEY")
        #expect(try service.retrieveNoninteractive(for: "LOCK_KEY") == "v2")
    }

    @Test("Delete of a missing key is idempotent (rc=44)")
    func deleteIdempotentMissing() throws {
        let (service, _) = try makeStub()
        // 保存していないキーの削除は throw しない（44 冪等）
        try service.delete(for: "NEVER_SAVED_KEY")
    }
}
