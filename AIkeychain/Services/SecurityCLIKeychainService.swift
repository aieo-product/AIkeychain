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

    /// 旧 GUI ストアの service 名（読み取り fallback / 削除時の掃除にのみ使う）。
    static let legacyGUIService = "com.aieo.aikeychain"

    /// 値の最大長。stdin 一括書き込みのパイプバッファ束縛（save() 参照）。
    static let maxValueLength = 8192

    private let securityBin = "/usr/bin/security"
    /// subprocess 読み取りの上限。プロンプト待ち等でブロックした子はこれで kill する。
    /// Proxy の外側タイムアウト(3s)より短くし、permit を先に返せるようにする。
    var readTimeout: TimeInterval = 2.5
    var writeTimeout: TimeInterval = 10

    /// テスト専用: stub security への差し替え口。#117 の絶対パス主義を守るため、
    /// 環境変数ではなくコード（@testable）からのみ変更できる internal プロパティにする。
    var securityBinOverrideForTesting: String?

    /// テスト専用: ロック検出の差し替え口（実 Keychain の状態に依存させない）。
    var keychainLockedProbeForTesting: (() -> Bool)?

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
        // 純粋な入力検証はロック判定より先に行う: 外部状態（ロック）で不正入力の
        // エラー種別が interactionRequired に化けると、呼び出し側の
        // unsupported/failed 分類が解錠の前後で変わってしまう（#183 レビュー SF-2）
        guard EnvVarName.isValid(account) else {
            throw KeychainError.invalidAccount
        }
        // `security find -w` は値に非 ASCII/制御文字が含まれると hex を出力する。
        // 「hex らしき出力を復号する」推測は all-hex の正規シークレット
        // （例 "4142..."）を破壊するため行わない（#179 レビュー CONFIRMED）。
        // 代わりに保存側で printable ASCII のみに制限し、読み出しが常に raw に
        // なることを保証する。非 ASCII/複数行の対応は C7 #174 で規約を決めてから。
        guard value.range(of: "^[\\x20-\\x7e]+$", options: .regularExpression) != nil else {
            throw KeychainError.invalidData
        }
        // 長さ上限: hex 展開後も `security -i` への stdin 一括書き込みがパイプ
        // バッファ (64KB) 内に収まることを保証する（超えると「親は write で、子は
        // 出力でブロック」のデッドロックが timeout の外で起き得る — #179 二段レビュー）。
        // CLI (cli/src/keychain.js) と同じ値。
        guard value.count <= Self.maxValueLength else {
            throw KeychainError.invalidData
        }
        try ensureKeychainUnlocked()

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
        try ensureKeychainUnlocked()
        return try subprocessRead(account: account, timeout: writeTimeout)
    }

    func retrieveNoninteractive(for account: String) throws -> String? {
        // ロック中は spawn せず即時失敗（quarantine より前 — ロックはキー単位の
        // 状態ではないので、解錠後まで 60 秒隔離を残さない）
        try ensureKeychainUnlocked()
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
        try ensureKeychainUnlocked()
        // 掃除の順序が要（#179 二段レビュー B3）: fallback ストア（manual → 旧 GUI）を
        // **先に**消し、権威コピー（managed）を最後に消す。逆順で legacy 掃除が失敗すると
        // 「削除成功と報告したのに `akc get` の fallback が古い値を解決し続ける」状態になる。
        // fallback 掃除が失敗した場合は managed に触らず throw する — キーは無傷のまま
        // 解決可能で、ユーザーには削除失敗が見える（half-deleted 状態を作らない）。

        if EnvVarName.isManualSchemeCandidate(account) {
            // manual スキームは厳格名（大文字スネーク）のみ対象（#163 と同じガード —
            // 他アプリの小文字/ドット付き service 名アイテムを巻き添えにしない）。
            // `delete-generic-password -s NAME` は最初に一致した 1 件しか消さないため、
            // 重複エントリ（#100）が残らないよう 44 (not found) まで繰り返す。
            var remaining = 10 // 暴走防止の上限（実キーチェーンで重複が 10 超は想定外）
            while remaining > 0 {
                remaining -= 1
                switch runSecurity(arguments: ["delete-generic-password", "-s", account],
                                   stdin: nil, timeout: writeTimeout) {
                case .exited(0, _, _):
                    continue
                case .exited(44, _, _):
                    remaining = 0
                case .exited(let status, _, _):
                    throw KeychainError.unexpectedStatus(OSStatus(status))
                case .timedOut:
                    throw KeychainError.interactionRequired
                case .failedToLaunch:
                    throw KeychainError.unexpectedStatus(errSecIO)
                }
            }
        }

        // 旧 GUI ストアの同名コピー。旧 GUI 所有はプロンプトになり得るが、削除は
        // headed 前提の操作なので許容（timeout なら throw し、managed は無傷）。
        switch runSecurity(arguments: ["delete-generic-password", "-s", Self.legacyGUIService, "-a", account],
                           stdin: nil, timeout: writeTimeout) {
        case .exited(0, _, _), .exited(44, _, _):
            break
        case .exited(let status, _, _):
            throw KeychainError.unexpectedStatus(OSStatus(status))
        case .timedOut:
            throw KeychainError.interactionRequired
        case .failedToLaunch:
            throw KeychainError.unexpectedStatus(errSecIO)
        }

        // 最後に権威コピー（managed）。44 は冪等成功扱い（従来の delete と同じ意味論）。
        switch runSecurity(arguments: ["delete-generic-password", "-s", Self.managedService, "-a", account],
                           stdin: nil, timeout: writeTimeout) {
        case .exited(0, _, _), .exited(44, _, _):
            break
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
        // manual スキーム (service=<キー名>) の発見。値は読まない属性列挙なので
        // 所有者に関係なく無音（旧 KeychainService と同じ実装 / #160）。
        // #167 では最終的に manual スキーム自体を廃止するが、その置き換えは
        // C5 (#172) 移行アシスタント / C7 (#174) の担当。C2 で列挙まで止めると
        // (a) 既存 manual キーが GUI から突然消える、(b) delete() は manual コピーを
        // 掃除するのに KeyEditorViewModel.deletesManualEntryToo の巻き添え警告が
        // 恒久 false になり無警告削除が走る（#179 二段レビュー B4）。
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
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
            guard let svc = item[kSecAttrService as String] as? String,
                  svc != Self.managedService,
                  svc != Self.legacyGUIService,
                  EnvVarName.isManualSchemeCandidate(svc),
                  seen.insert(svc).inserted else { return nil }
            return svc
        }
    }

    // MARK: - ロック検出 (#170: #169 チェックリストの残)

    /// default keychain がロックされているか。ロック中の subprocess `security` は
    /// SecurityAgent の解錠ダイアログでブロックし timeout-kill 行きになるため、
    /// spawn 前に検出して UI を出さず即時失敗させる（Proxy は 503 に写像される）。
    /// SecKeychain* API は deprecated だがロック状態を無音で読める代替が無い。
    private func isDefaultKeychainLocked() -> Bool {
        if let probe = keychainLockedProbeForTesting { return probe() }
        var keychain: SecKeychain?
        guard SecKeychainCopyDefault(&keychain) == errSecSuccess, let keychain else {
            return false // 判定不能はブロックしない（従来挙動 = timeout に委ねる）
        }
        var status = SecKeychainStatus(0)
        guard SecKeychainGetStatus(keychain, &status) == errSecSuccess else { return false }
        return (status & SecKeychainStatus(kSecUnlockStateStatus)) == 0
    }

    /// ロック中は interactionRequired を即時 throw する。quarantine はしない
    /// （ロックはキー単位でなく全体の状態で、解錠後に 60 秒待たせる理由が無い）。
    private func ensureKeychainUnlocked() throws {
        if isDefaultKeychainLocked() {
            throw KeychainError.interactionRequired
        }
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
            // 保存側が printable ASCII のみを許容するため、-w の出力は常に raw。
            // hex 推測復号は all-hex の正規値を破壊するので行わない（#179 レビュー）。
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

        do {
            try process.run()
        } catch {
            // 一時的な資源枯渇 (fork EAGAIN 等) は 1 回だけ短い待機後に再試行する
            usleep(50_000)
            do { try process.run() } catch { return .failedToLaunch }
        }

        // 出力の吸い上げは **stdin 書き込みより先に** 開始する（パイプ詰まりで
        // 「親は write・子は出力」の相互ブロックを作らない — #179 二段レビュー S4）。
        // バッファはロック越しにのみ触り、timeout 帰還後にクロージャが走っても
        // 呼び出し元とデータ競合しないようにする。
        let ioLock = NSLock()
        var stdoutData = Data(), stderrData = Data()
        let ioGroup = DispatchGroup()
        ioGroup.enter()
        DispatchQueue.global().async {
            let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            ioLock.lock(); stdoutData = data; ioLock.unlock()
            ioGroup.leave()
        }
        ioGroup.enter()
        DispatchQueue.global().async {
            let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            ioLock.lock(); stderrData = data; ioLock.unlock()
            ioGroup.leave()
        }

        // stdin は同期書き込みでよい: save() が値長を maxValueLength に制限するため
        // コマンド全体が hex 展開後もパイプバッファ (64KB) に収まり、ブロックしない。
        if let stdin {
            stdinPipe.fileHandleForWriting.write(stdin.data(using: .utf8)!)
        }
        stdinPipe.fileHandleForWriting.closeFile()

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
            return .timedOut // バッファには触らない（読み手がまだ走っていても安全）
        }

        process.waitUntilExit()
        // 排出待ちは subprocess 本体と同等の猶予を与える。短すぎると正常終了した
        // 読み取りを（GCD スレッドが混雑しているだけで）timeout 扱いに誤変換する
        guard ioGroup.wait(timeout: .now() + max(2, timeout)) == .success else {
            // 子孫プロセスが pipe を握り続けて出力が閉じない異常系。不完全な出力を
            // 「成功した読み取り値」として返さない（値の取り違えを防ぐ）。
            return .timedOut
        }
        ioLock.lock()
        let out = stdoutData, err = stderrData
        ioLock.unlock()
        return .exited(process.terminationStatus, stdout: out, stderr: err)
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
