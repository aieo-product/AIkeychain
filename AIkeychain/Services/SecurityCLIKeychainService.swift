import Foundation
import Security

/// `/usr/bin/security` を単一の作成/更新アイデンティティとする Keychain アクセス層 (#167/#169)。
///
/// ## なぜ subprocess か（実測根拠は #168 の E6/S6/S7'/S5）
/// macOS のヘッドレス読み取りは「復号 trusted-app リスト」かつ「PartitionID リスト」の
/// 2 重ゲートで、既定では**作成したプロセスだけ**が両方を満たす。GUI が in-process で
/// 書いたキーは `akc run`（= security CLI）から読めず、逆も然り。よって:
/// - **書き込みは必ず子プロセス `/usr/bin/security`**（作成者 = security → akc がヘッドレスで読める。S6 で LaunchServices 起動アプリの子でも成立を実証）
/// - **値の読み取りも subprocess**（security 所有アイテムの in-process 読みは ~7 秒ブロック + SecurityAgent 起動 — E6-1）
/// - **一覧・存在確認だけは in-process の属性照会**（値を読まなければ所有者に関係なく無音）
///
/// ## managed namespace
/// 書き込み先 service は `com.aieo.aikeychain.managed` に固定。「managed の下のキー =
/// security が作成」という不変条件により、所有者判別（マーカー等）そのものを不要にする。
/// 旧 service（com.aieo.aikeychain / manual スキーム）へは一切書かない。
///
/// ## セキュリティ規約（#94/#117 踏襲）
/// - security は**絶対パス**で起動（PATH ハイジャック防止）
/// - 値は `security -i` の stdin + hex で渡す（argv / 環境変数に露出させない）
/// - stderr はエラー整形時に hex/値を redact
final class SecurityCLIKeychainService: KeychainServiceProtocol {
    static let shared = SecurityCLIKeychainService()

    /// managed namespace（#167 オーナー決定）。旧 com.aieo.aikeychain とは別名にすることで
    /// 復元/同期/旧アプリ由来の GUI 所有アイテムが混入しても不変条件が壊れない。
    static let managedService = "com.aieo.aikeychain.managed"

    private let securityBin = "/usr/bin/security"
    /// subprocess 読み取りの上限。プロンプト待ち等でブロックした子はこれで kill する。
    /// Proxy の外側タイムアウト(3s)より短くし、permit を先に返せるようにする。
    var readTimeout: TimeInterval = 2.5
    var writeTimeout: TimeInterval = 10

    /// テスト専用: stub security への差し替え口。#117 の絶対パス主義を守るため、
    /// 環境変数ではなくコード（@testable）からのみ変更できる internal プロパティにする。
    var securityBinOverrideForTesting: String?

    private var effectiveSecurityBin: String { securityBinOverrideForTesting ?? securityBin }

    // MARK: - 直列化・coalescing・quarantine (#169 Proxy ハードニング)

    private let stateLock = NSLock()
    /// key → 実行中の読み取り。同一キーへの並行読みを 1 本の subprocess に束ねる
    /// （Proxy への同時リクエストで security を多重 spawn しない）。
    private var inflightReads: [String: ReadTask] = [:]
    /// timeout-kill が発生したキーの隔離。TTL まで即時 interactionRequired を返し、
    /// ダイアログ/spawn の連発を防ぐ。成功した save で解除される。
    private var quarantinedUntil: [String: Date] = [:]
    private let quarantineTTL: TimeInterval = 60

    private final class ReadTask {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<String?, Error>?
    }

    // MARK: - KeychainServiceProtocol

    func save(value: String, for account: String) throws {
        guard EnvVarName.isValid(account) else {
            throw KeychainError.invalidAccount
        }
        // CLI (cli/src/keychain.js) と同じ制約: 制御文字は `find -w` の読み戻しを
        // hex 出力に化けさせラウンドトリップを壊すため保存前に拒否する。
        // （複数行値の許容は C7 #174 で読み書き両側の規約を揃えてから）
        guard value.range(of: "[\\x00-\\x1f\\x7f]", options: .regularExpression) == nil else {
            throw KeychainError.invalidData
        }
        guard !value.isEmpty else { throw KeychainError.invalidData }

        let hex = value.data(using: .utf8)!.map { String(format: "%02x", $0) }.joined()
        // -U: 既存アイテムの更新。security 所有アイテムへの -U は所有権・headless
        // 読み取りを保つことを実測済み（#168 S7'）。
        let command = "add-generic-password -U -s \"\(Self.managedService)\" -a \"\(account)\" -X \(hex)\n"
        let result = runSecurity(arguments: ["-i"], stdin: command, timeout: writeTimeout)
        guard case .exited(let status, _, let stderr) = result, status == 0 else {
            throw KeychainError.unexpectedStatus(errSecIO).annotated(redact(resultDescription(result, stderr: true)))
        }
        _ = stderr

        // 書き込みの読み戻し検証（CLI の setKey と同じ: -U は不整合状態でも成功を
        // 報告し得るため、実際に保存された値を確認する）
        guard let readBack = try retrieve(for: account), readBack == value else {
            throw KeychainError.invalidData
        }

        // 成功した書き込みは quarantine を解除する
        stateLock.lock()
        quarantinedUntil[account] = nil
        stateLock.unlock()
    }

    func retrieve(for account: String) throws -> String? {
        try subprocessRead(account: account, timeout: writeTimeout)
    }

    func retrieveNoninteractive(for account: String) throws -> String? {
        // Proxy 経路: quarantine 済みキーは spawn せず即時失敗（fail fast）
        stateLock.lock()
        if let until = quarantinedUntil[account], until > Date() {
            stateLock.unlock()
            throw KeychainError.interactionRequired
        }
        // 同一キーの読みが実行中ならそれに相乗りする（coalescing）
        if let existing = inflightReads[account] {
            stateLock.unlock()
            existing.semaphore.wait()
            existing.semaphore.signal() // 後続の待ち手にも伝播
            switch existing.result {
            case .success(let v): return v
            case .failure(let e): throw e
            case nil: throw KeychainError.interactionRequired
            }
        }
        let task = ReadTask()
        inflightReads[account] = task
        stateLock.unlock()

        defer {
            stateLock.lock()
            inflightReads[account] = nil
            stateLock.unlock()
            task.semaphore.signal()
        }

        do {
            let value = try subprocessRead(account: account, timeout: readTimeout)
            task.result = .success(value)
            return value
        } catch {
            if case KeychainError.interactionRequired = error {
                // timeout-kill（プロンプト待ち相当）→ 隔離してダイアログ/spawn 連発を防ぐ
                stateLock.lock()
                quarantinedUntil[account] = Date().addingTimeInterval(quarantineTTL)
                stateLock.unlock()
            }
            task.result = .failure(error)
            throw error
        }
    }

    func delete(for account: String) throws {
        let result = runSecurity(
            arguments: ["delete-generic-password", "-s", Self.managedService, "-a", account],
            stdin: nil, timeout: writeTimeout)
        switch result {
        case .exited(0, _, _):
            return
        case .exited(44, _, _):
            return // not found は冪等成功扱い（従来の delete と同じ意味論）
        case .exited(let status, _, _):
            throw KeychainError.unexpectedStatus(OSStatus(status))
        case .timedOut:
            throw KeychainError.interactionRequired
        case .failedToLaunch:
            throw KeychainError.unexpectedStatus(errSecIO)
        }
    }

    func exists(for account: String) -> Bool {
        // 属性のみの in-process 照会（値を読まない = 所有者に関係なく無音）
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.managedService,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    func allAccounts() -> [String] {
        // managed namespace の列挙（in-process 属性照会・無音）
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.managedService,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            return []
        }
        var seen = Set<String>()
        return items.compactMap { item -> String? in
            guard let acct = item[kSecAttrAccount as String] as? String,
                  seen.insert(acct).inserted else { return nil }
            return acct
        }
    }

    func manualServices() -> [String] {
        // managed namespace 移行に伴い manual スキームの発見は廃止 (#167)。
        // 旧キーは移行アシスタント (C5 #172) の専用導線でのみ扱う。
        []
    }

    // MARK: - subprocess 基盤

    private enum RunResult {
        case exited(Int32, stdout: Data, stderr: Data)
        case timedOut
        case failedToLaunch
    }

    private func subprocessRead(account: String, timeout: TimeInterval) throws -> String? {
        let result = runSecurity(
            arguments: ["find-generic-password", "-s", Self.managedService, "-a", account, "-w"],
            stdin: nil, timeout: timeout)
        switch result {
        case .exited(0, let stdout, _):
            var text = String(data: stdout, encoding: .utf8) ?? ""
            if text.hasSuffix("\n") { text.removeLast() }
            // security -w は非 ASCII 値を hex で出力する。保存側（save/akc set）は
            // hex 入力なので、偶数長 hex + UTF-8 復号可能なら復号を試す。
            // ASCII のみの実値が hex 文字だけで構成されるケースは save 側の
            // read-back 検証で弾かれるため実害は限定的（CLI と同じ扱い）。
            if let decoded = Self.decodeHexIfLikely(text) { text = decoded }
            return text
        case .exited(44, _, _):
            return nil
        case .exited(let status, _, _):
            throw KeychainError.unexpectedStatus(OSStatus(status))
        case .timedOut:
            // プロンプト待ち等でブロック → kill 済み。呼び出し側の意味論は「要対話」。
            throw KeychainError.interactionRequired
        case .failedToLaunch:
            throw KeychainError.unexpectedStatus(errSecIO)
        }
    }

    /// security を絶対パスで起動し、timeout で**プロセスグループごと** SIGKILL する。
    /// S5 実測: kill 後のセッションはモーダルブロックされず、ゾンビも残らない。
    private func runSecurity(arguments: [String], stdin: String?, timeout: TimeInterval) -> RunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: effectiveSecurityBin)
        process.arguments = arguments
        // 環境は最小化（PATH 固定・DYLD_* 等を渡さない）
        process.environment = ["PATH": "/usr/bin:/bin"]

        let stdoutPipe = Pipe(), stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        let stdinPipe = Pipe()
        process.standardInput = stdinPipe

        do { try process.run() } catch { return .failedToLaunch }

        if let stdin {
            stdinPipe.fileHandleForWriting.write(stdin.data(using: .utf8)!)
        }
        stdinPipe.fileHandleForWriting.closeFile()

        // 出力はバックグラウンドで吸い上げる（パイプ詰まりで子が固まらないように）
        var stdoutData = Data(), stderrData = Data()
        let ioGroup = DispatchGroup()
        ioGroup.enter()
        DispatchQueue.global().async {
            stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            ioGroup.leave()
        }
        ioGroup.enter()
        DispatchQueue.global().async {
            stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            ioGroup.leave()
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            usleep(20_000) // 20ms
        }

        if process.isRunning {
            // プロセスグループごと SIGKILL（security が子を持つ場合も回収）
            kill(-process.processIdentifier, SIGKILL)
            process.terminate()
            kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit() // reap（ゾンビ防止, S5 実測どおり）
            _ = ioGroup.wait(timeout: .now() + 1)
            return .timedOut
        }

        process.waitUntilExit()
        _ = ioGroup.wait(timeout: .now() + 2)
        return .exited(process.terminationStatus, stdout: stdoutData, stderr: stderrData)
    }

    /// 偶数長の hex 文字列で、かつ UTF-8 として復号できる場合のみ復号して返す。
    static func decodeHexIfLikely(_ text: String) -> String? {
        guard !text.isEmpty, text.count % 2 == 0,
              text.range(of: "^[0-9a-fA-F]+$", options: .regularExpression) != nil else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(text.count / 2)
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            guard let byte = UInt8(text[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return String(bytes: bytes, encoding: .utf8)
    }

    private func resultDescription(_ result: RunResult, stderr: Bool) -> String {
        switch result {
        case .exited(let status, _, let err):
            let msg = stderr ? (String(data: err, encoding: .utf8) ?? "") : ""
            return "security exited \(status): \(msg)"
        case .timedOut: return "security timed out"
        case .failedToLaunch: return "security failed to launch"
        }
    }

    /// stderr に混入し得る hex 値（= シークレット）を redact する（#94 系）
    private func redact(_ message: String) -> String {
        message.replacingOccurrences(of: "-X [0-9a-fA-F]+", with: "-X <redacted>",
                                     options: .regularExpression)
    }
}

private extension KeychainError {
    /// 追加コンテキストは debug ログ用途。ユーザー向け文言は KeychainError 側の定義を使う。
    func annotated(_ context: String) -> KeychainError {
        #if DEBUG
        NSLog("[SecurityCLIKeychainService] %@", context)
        #endif
        return self
    }
}
