import Foundation
import Network
import Observation

/// ローカル認証プロキシサーバー
/// localhost でリクエストを受け付け、Keychain からAPIキーを読み取り、
/// Authorization ヘッダを注入して上流に転送する。
/// AI プロセスの環境変数に API キーを露出させない。
@Observable
final class ProxyServer {
    var isRunning: Bool = false
    var port: UInt16 = AppState.defaultPort
    var requestCount: Int = 0
    var lastError: String?

    /// セッションごとのランダム認証トークン（プロキシ起動時に生成）
    private(set) var sessionToken: String = ""
    static let tokenHeaderName = "X-AIKeyChain-Token"

    private var listener: NWListener?
    private let keychainService: KeychainServiceProtocol
    /// listener 専用（接続受理は軽量・直列で十分）
    private let queue = DispatchQueue(label: "com.aieo.aikeychain.proxy", qos: .userInitiated)
    /// 接続ごとの処理は並列キューで行う。1 本の遅い/ブロックしたリクエストが
    /// 他のリクエスト（403/502 など即応すべき経路を含む）を巻き込まないようにする。
    private let processingQueue = DispatchQueue(
        label: "com.aieo.aikeychain.proxy.processing", qos: .userInitiated, attributes: .concurrent)

    /// Keychain 読み取りのタイムアウト（consent UI 抑止が効かないレガシー ACL でも有限時間で打ち切る保険）
    private let keychainTimeout: TimeInterval
    /// 上流接続・受信のタイムアウト
    private let upstreamTimeout: TimeInterval
    /// Keychain が consent/タイムアウトで利用不能になった後、再試行を抑止する期間。
    /// タイムアウトしても背後の `SecItemCopyMatching` スレッドは即座には解放されないため、
    /// このサーキットブレーカーが無いと連続リクエストでスレッドが滞留・枯渇し得る。
    private let keychainCooldown: TimeInterval
    /// クライアントが接続後リクエストを送らない場合に接続を破棄するまでの猶予（slowloris 対策）。
    private let inboundTimeout: TimeInterval
    /// 受信リクエスト全体（ヘッダ + ボディ）の最大サイズ。超過は 413 で拒否し、
    /// 巨大ボディによるメモリ膨張を防ぐ。
    private let maxRequestBytes: Int

    private let breakerLock = NSLock()
    private var keychainUnavailableUntil: Date?

    /// 上流接続の生成（既定は TLS:443）。テストではローカルの平文サーバーへ
    /// 差し替えてストリーミング/フレーミングを検証できるようにする。
    private let makeUpstream: (_ host: String) -> NWConnection

    init(keychainService: KeychainServiceProtocol = KeychainService.shared,
         keychainTimeout: TimeInterval = 3,
         upstreamTimeout: TimeInterval = 30,
         keychainCooldown: TimeInterval = 10,
         maxConcurrentKeychainReads: Int = 4,
         inboundTimeout: TimeInterval = 15,
         maxRequestBytes: Int = 10 * 1024 * 1024,
         makeUpstream: ((_ host: String) -> NWConnection)? = nil) {
        self.keychainService = keychainService
        self.keychainTimeout = keychainTimeout
        self.upstreamTimeout = upstreamTimeout
        self.keychainCooldown = keychainCooldown
        self.inboundTimeout = inboundTimeout
        self.maxRequestBytes = max(8 * 1024, maxRequestBytes)
        self.keychainAdmission = DispatchSemaphore(value: max(1, maxConcurrentKeychainReads))
        self.makeUpstream = makeUpstream ?? { host in
            NWConnection(host: NWEndpoint.Host(host), port: .https, using: NWParameters.tls)
        }
    }

    /// サーキットブレーカー: クールダウン中なら true（読み取りを試みない）。
    private func keychainInCooldown() -> Bool {
        breakerLock.lock(); defer { breakerLock.unlock() }
        guard let until = keychainUnavailableUntil else { return false }
        if Date() >= until {
            keychainUnavailableUntil = nil
            return false
        }
        return true
    }

    private func tripKeychainBreaker() {
        breakerLock.lock(); defer { breakerLock.unlock() }
        keychainUnavailableUntil = Date().addingTimeInterval(keychainCooldown)
    }

    private func resetKeychainBreaker() {
        breakerLock.lock(); defer { breakerLock.unlock() }
        keychainUnavailableUntil = nil
    }

    /// クライアントへの応答が一度だけ行われることを保証する（タイムアウトと正常完了の競合対策）。
    private final class OneShot {
        private let lock = NSLock()
        private var fired = false
        func consume() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if fired { return false }
            fired = true
            return true
        }
    }

    /// 非活動タイムアウト。`reschedule()` のたびに期限を延ばし、無通信が `interval`
    /// 続いたら一度だけ `onFire` を呼ぶ。ストリーミング応答（SSE 等の長時間接続）を
    /// 許容しつつ、上流の沈黙やクライアント停止で永久に滞留しないようにする。
    private final class InactivityTimer {
        private let queue: DispatchQueue
        private let interval: TimeInterval
        private let onFire: () -> Void
        private let lock = NSLock()
        private var stopped = false
        private var didFire = false
        /// 世代トークン。reschedule のたびに増やし、fire は自分の世代が最新の
        /// ときだけ発火する。既にキューから取り出され実行に入った古い work item が
        /// 「キャンセルされたはず」のまま発火してアクティブなストリームを誤って
        /// 閉じる事故を防ぐ。
        private var generation = 0

        init(queue: DispatchQueue, interval: TimeInterval, onFire: @escaping () -> Void) {
            self.queue = queue
            self.interval = interval
            self.onFire = onFire
        }

        func reschedule() {
            lock.lock(); defer { lock.unlock() }
            if stopped || didFire { return }
            generation += 1
            let gen = generation
            let work = DispatchWorkItem { [weak self] in self?.fire(gen) }
            queue.asyncAfter(deadline: .now() + interval, execute: work)
        }

        private func fire(_ gen: Int) {
            lock.lock()
            if stopped || didFire || gen != generation { lock.unlock(); return }
            didFire = true
            lock.unlock()
            onFire()
        }

        func stop() {
            lock.lock(); defer { lock.unlock() }
            stopped = true
            generation += 1 // 予約済みの fire を無効化
        }
    }

    private enum KeyReadResult {
        case success(String)
        case notFound
        case interactionRequired
        case timedOut
        case busy
        case error(String)
    }

    /// 同時に走る Keychain 読み取り数の上限。ブロックした読み取りの背後スレッドは
    /// タイムアウト後も滞留するため、サーキットブレーカーが開く前（最初の
    /// keychainTimeout 窓）の同時バーストでもスレッドが無制限に増えないよう上限化する。
    private let keychainAdmission: DispatchSemaphore

    func start() throws {
        guard !isRunning else { return }
        sessionToken = UUID().uuidString

        let params = NWParameters.tcp
        params.acceptLocalOnly = true // localhost のみ
        params.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: .ipv4(.loopback),
            port: NWEndpoint.Port(rawValue: port)!
        )

        let nwListener = try NWListener(using: params)

        nwListener.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self?.isRunning = true
                    self?.lastError = nil
                case .failed(let error):
                    self?.isRunning = false
                    self?.lastError = error.localizedDescription
                case .cancelled:
                    self?.isRunning = false
                default:
                    break
                }
            }
        }

        nwListener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        nwListener.start(queue: queue)
        self.listener = nwListener
    }

    func stop() {
        listener?.cancel()
        listener = nil
        DispatchQueue.main.async {
            self.isRunning = false
        }
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        // 並列キューで処理することで、1 接続のブロックが他をブロックしない。
        connection.start(queue: processingQueue)

        // 接続後にリクエストを送ってこないクライアントで接続が滞留しないよう破棄する。
        let idleTimeout = DispatchWorkItem { connection.cancel() }
        processingQueue.asyncAfter(deadline: .now() + inboundTimeout, execute: idleTimeout)

        receiveRequest(connection: connection, buffer: Data(), idleTimeout: idleTimeout)
    }

    /// リクエストを「ヘッダ終端（CRLFCRLF）＋ Content-Length 分のボディ」が
    /// 揃うまで蓄積してから処理する。1 回の receive で全体が届く保証はないため
    /// （大きい POST ボディや分割到着で取りこぼさないように）。
    private func receiveRequest(connection: NWConnection, buffer: Data, idleTimeout: DispatchWorkItem) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { connection.cancel(); return }

            var buffer = buffer
            if let data { buffer.append(data) }

            if error != nil {
                idleTimeout.cancel()
                connection.cancel()
                return
            }

            // リクエストが大きすぎる → 413 で拒否（メモリ膨張防止）。
            if buffer.count > self.maxRequestBytes {
                idleTimeout.cancel()
                self.sendErrorResponse(connection: connection, statusCode: 413, message: "Request too large")
                return
            }

            // ヘッダが揃ったか？
            if let headerEnd = buffer.firstRange(of: Data("\r\n\r\n".utf8)) {
                let headerData = buffer[buffer.startIndex..<headerEnd.lowerBound]
                switch Self.contentLengthField(from: headerData) {
                case .invalid:
                    idleTimeout.cancel()
                    self.sendErrorResponse(connection: connection, statusCode: 400, message: "Invalid or conflicting Content-Length")
                    return
                case .absent, .present:
                    let contentLength = Self.contentLengthValue(from: headerData)
                    let bodyReceived = buffer.distance(from: headerEnd.upperBound, to: buffer.endIndex)
                    if bodyReceived >= contentLength {
                        idleTimeout.cancel()
                        self.processRequest(data: buffer, connection: connection)
                        return
                    }
                }
            }

            if isComplete {
                // 相手が送信を終えた（が枠が完結していない）—持っている分で処理を試みる。
                idleTimeout.cancel()
                if buffer.isEmpty {
                    connection.cancel()
                } else {
                    self.processRequest(data: buffer, connection: connection)
                }
                return
            }

            // まだ足りない—受信を継続。
            self.receiveRequest(connection: connection, buffer: buffer, idleTimeout: idleTimeout)
        }
    }

    enum ContentLengthField { case absent; case present; case invalid }

    /// Content-Length ヘッダを厳密に検証する。非数値・負値・値の異なる重複
    /// （リクエストスマグリング対策）は invalid。
    static func contentLengthField(from headerData: Data) -> ContentLengthField {
        guard let text = String(data: headerData, encoding: .utf8) else { return .invalid }
        var found: Int?
        for line in text.components(separatedBy: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" else { continue }
            let raw = parts[1].trimmingCharacters(in: .whitespaces)
            guard let n = Int(raw), n >= 0 else { return .invalid }
            if let prev = found, prev != n { return .invalid }
            found = n
        }
        return found == nil ? .absent : .present
    }

    /// 検証済み前提で Content-Length の数値を返す（無ければ 0）。
    static func contentLengthValue(from headerData: Data) -> Int {
        guard let text = String(data: headerData, encoding: .utf8) else { return 0 }
        for line in text.components(separatedBy: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                return Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        return 0
    }

    /// ヘッダバイト列から Content-Length を取り出す（無ければ 0）。テスト/上流補助用。
    static func parseContentLength(from headerData: Data) -> Int {
        contentLengthValue(from: headerData)
    }

    /// Keychain 読み取りを非対話・タイムアウト付きで実行する。
    /// 非対話読み取りでも万一ブロックした場合に備え、別キューで実行して
    /// `keychainTimeout` で打ち切る（処理スレッドを占有させない）。
    /// 同時実行数は `keychainAdmission` で上限化し、ブロックした読み取りスレッドが
    /// バーストで無制限に増えるのを防ぐ。
    private func readKeyWithTimeout(account: String) -> KeyReadResult {
        // 空きが無ければ（=上限数の読み取りが既にブロック中なら）即座に busy で返す。
        guard keychainAdmission.wait(timeout: .now()) == .success else {
            return .busy
        }

        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var outcome: KeyReadResult = .timedOut

        DispatchQueue.global(qos: .userInitiated).async { [keychainService, keychainAdmission] in
            // permit は SecItemCopyMatching が実際に返るまで保持する
            // （readKeyWithTimeout のタイムアウト時点ではなく）。これにより
            // 「ブロック中スレッド数 ≤ 上限」が保証される。
            defer { keychainAdmission.signal() }
            var local: KeyReadResult
            do {
                if let value = try keychainService.retrieveNoninteractive(for: account), !value.isEmpty {
                    local = .success(value)
                } else {
                    local = .notFound
                }
            } catch KeychainError.interactionRequired {
                local = .interactionRequired
            } catch {
                local = .error(error.localizedDescription)
            }
            lock.lock(); outcome = local; lock.unlock()
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + keychainTimeout) == .timedOut {
            return .timedOut
        }
        lock.lock(); defer { lock.unlock() }
        return outcome
    }

    private func processRequest(data: Data, connection: NWConnection) {
        // 受信したリクエストはすべて requestCount に計上
        DispatchQueue.main.async { [weak self] in self?.requestCount += 1 }

        guard let requestString = String(data: data, encoding: .utf8) else {
            AppState.shared.proxyLogStore.append(ProxyLog(
                timestamp: Date(), service: "(invalid)",
                method: "?", path: "?",
                statusCode: 400, latency: 0, isError: true
            ))
            sendErrorResponse(connection: connection, statusCode: 400, message: "Invalid request")
            return
        }

        // Parse HTTP request
        guard let parsed = HTTPRequestParser.parse(requestString, body: data) else {
            AppState.shared.proxyLogStore.append(ProxyLog(
                timestamp: Date(), service: "(unparseable)",
                method: "?", path: "?",
                statusCode: 400, latency: 0, isError: true
            ))
            sendErrorResponse(connection: connection, statusCode: 400, message: "Failed to parse HTTP request")
            return
        }

        // セッショントークン認証（必須）
        let tokenHeader = parsed.headers.first(where: { $0.name.lowercased() == Self.tokenHeaderName.lowercased() })?.value
        guard tokenHeader == sessionToken, !sessionToken.isEmpty else {
            AppState.shared.proxyLogStore.append(ProxyLog(
                timestamp: Date(), service: parsed.host,
                method: parsed.method, path: parsed.path,
                statusCode: 403, latency: 0, isError: true
            ))
            sendErrorResponse(connection: connection, statusCode: 403, message: "Missing or invalid session token")
            return
        }

        // Find route for this host
        guard let route = ProxyRoute.route(for: parsed.host) else {
            AppState.shared.proxyLogStore.append(ProxyLog(
                timestamp: Date(), service: parsed.host,
                method: parsed.method, path: parsed.path,
                statusCode: 502, latency: 0, isError: true
            ))
            sendErrorResponse(connection: connection, statusCode: 502, message: "No proxy route for host: \(parsed.host)")
            return
        }

        // Circuit breaker: if a recent read was consent-blocked/timed out, fail
        // fast without dispatching another read (whose backing SecItemCopyMatching
        // thread would otherwise pile up while the prompt remains unanswered).
        if keychainInCooldown() {
            respondReadFailure(connection: connection, route: route, parsed: parsed,
                               statusCode: 503, message: "Keychain temporarily unavailable (consent/unlock required). Open AI KeyChain and approve access, then retry.")
            return
        }

        // Read API key from Keychain — non-interactive and time-bounded so an
        // unattended proxy can never hang on a SecurityAgent consent prompt.
        let apiKey: String
        switch readKeyWithTimeout(account: route.keychainAccount) {
        case .success(let value):
            resetKeychainBreaker()
            apiKey = value
        case .notFound:
            respondReadFailure(connection: connection, route: route, parsed: parsed,
                               statusCode: 401, message: "API key not found in Keychain for \(route.keychainAccount)")
            return
        case .interactionRequired:
            tripKeychainBreaker()
            respondReadFailure(connection: connection, route: route, parsed: parsed,
                               statusCode: 503, message: "Keychain access for \(route.keychainAccount) requires user consent/unlock. Open AI KeyChain and approve access, then retry.")
            return
        case .timedOut:
            tripKeychainBreaker()
            respondReadFailure(connection: connection, route: route, parsed: parsed,
                               statusCode: 504, message: "Keychain read for \(route.keychainAccount) timed out after \(Int(keychainTimeout))s")
            return
        case .busy:
            respondReadFailure(connection: connection, route: route, parsed: parsed,
                               statusCode: 503, message: "Keychain busy (too many concurrent reads blocked). Retry shortly.")
            return
        case .error(let detail):
            respondReadFailure(connection: connection, route: route, parsed: parsed,
                               statusCode: 502, message: "Keychain read error for \(route.keychainAccount): \(detail)")
            return
        }

        // Forward request with injected auth header
        forwardRequest(parsed: parsed, route: route, apiKey: apiKey, clientConnection: connection)
    }

    private func respondReadFailure(connection: NWConnection, route: ProxyRoute, parsed: HTTPRequestParser.ParsedRequest, statusCode: Int, message: String) {
        AppState.shared.proxyLogStore.append(ProxyLog(
            timestamp: Date(), service: route.host,
            method: parsed.method, path: parsed.path,
            statusCode: statusCode, latency: 0, isError: true
        ))
        sendErrorResponse(connection: connection, statusCode: statusCode, message: message)
    }

    // MARK: - Upstream Forwarding (NWConnection-based)

    private func forwardRequest(parsed: HTTPRequestParser.ParsedRequest, route: ProxyRoute, apiKey: String, clientConnection: NWConnection) {
        let requestStart = Date()

        // Build upstream HTTP request
        var requestLines = ["\(parsed.method) \(parsed.path) HTTP/1.1"]
        requestLines.append("Host: \(route.host)")

        // Inject auth header
        let headerValue = route.headerValuePrefix + apiKey
        requestLines.append("\(route.headerName): \(headerValue)")

        // Copy original headers (except Host, auth headers, and internal token)
        let tokenHeaderLower = Self.tokenHeaderName.lowercased()
        for (name, value) in parsed.headers {
            let lower = name.lowercased()
            if lower == "host" || lower == "authorization" || lower == "x-api-key" || lower == tokenHeaderLower { continue }
            requestLines.append("\(name): \(value)")
        }

        requestLines.append("Connection: close")
        requestLines.append("")
        requestLines.append("")

        var requestData = requestLines.joined(separator: "\r\n").data(using: .utf8)!
        if let body = parsed.body {
            requestData.append(body)
        }

        // Connect to upstream (TLS:443 by default; injectable for tests).
        let upstreamConnection = makeUpstream(route.host)

        // Guarantee exactly one client response even if the watchdog and a real
        // completion race each other.
        let responseGuard = OneShot()

        // Watchdog: never let a stuck upstream hang the client forever.
        let watchdog = DispatchWorkItem { [weak self] in
            guard let self, responseGuard.consume() else { return }
            upstreamConnection.cancel()
            self.logAndSend(
                clientConnection: clientConnection, requestStart: requestStart,
                route: route, parsed: parsed,
                message: "Upstream timed out after \(Int(self.upstreamTimeout))s"
            )
        }
        processingQueue.asyncAfter(deadline: .now() + upstreamTimeout, execute: watchdog)

        upstreamConnection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                // Connection established - send the request
                upstreamConnection.send(content: requestData, completion: .contentProcessed { sendError in
                    if let sendError {
                        watchdog.cancel()
                        guard responseGuard.consume() else { return }
                        self?.logAndSend(
                            clientConnection: clientConnection, requestStart: requestStart,
                            route: route, parsed: parsed,
                            message: "Upstream send error: \(sendError.localizedDescription)"
                        )
                        upstreamConnection.cancel()
                        return
                    }
                    // Receive upstream response
                    self?.receiveUpstreamResponse(
                        upstream: upstreamConnection, clientConnection: clientConnection,
                        requestStart: requestStart, route: route, parsed: parsed,
                        watchdog: watchdog, responseGuard: responseGuard
                    )
                })

            case .failed(let error):
                watchdog.cancel()
                guard responseGuard.consume() else { return }
                self?.logAndSend(
                    clientConnection: clientConnection, requestStart: requestStart,
                    route: route, parsed: parsed,
                    message: "Upstream connection failed: \(error.localizedDescription)"
                )
                upstreamConnection.cancel()

            default:
                break
            }
        }

        upstreamConnection.start(queue: processingQueue)
    }

    /// 上流レスポンスを**ストリーミング**でクライアントへ転送する（SSE 等に対応）。
    /// 各チャンクを受信即送信し、クライアント送信完了後に次のチャンクを読む
    /// （バックプレッシャー）。`upstreamTimeout` の**非活動**タイムアウトで、
    /// 上流の沈黙やクライアント停止による滞留を防ぐ（長時間ストリーム自体は許容）。
    private func receiveUpstreamResponse(upstream: NWConnection, clientConnection: NWConnection, requestStart: Date, route: ProxyRoute, parsed: HTTPRequestParser.ParsedRequest, watchdog: DispatchWorkItem, responseGuard: OneShot) {
        // 応答の所有権モデル:
        //  - `responseGuard`（呼び出し元と共有）: 「最初に確定した結末」を 1 つだけ許す。
        //    = ストリーミング開始 か、ストリーム前のエラー/タイムアウト 502 のどちらか。
        //  - `finish`: ストリーム開始後の終端処理（正常完了/切断/非活動）を 1 回だけ。
        var firstByte = true
        let statusLock = NSLock()
        var status = 200
        let finish = OneShot()
        var timer: InactivityTimer!

        // ストリーム開始後の終端: クライアント接続を閉じる（502 は返せない）。
        func closeAfterStream(truncated: Bool) {
            guard finish.consume() else { return }
            timer.stop()
            upstream.cancel()
            statusLock.lock(); let code = status; statusLock.unlock()
            AppState.shared.proxyLogStore.append(ProxyLog(
                timestamp: requestStart, service: route.host,
                method: parsed.method, path: parsed.path,
                statusCode: code, latency: Date().timeIntervalSince(requestStart),
                isError: truncated || code >= 400
            ))
            clientConnection.cancel()
        }

        // ストリーム開始前の終端: まだヘッダ未送信なので 502 を返せる。
        func failBeforeStream(_ message: String) {
            guard responseGuard.consume() else { return }
            timer.stop()
            watchdog.cancel()
            upstream.cancel()
            self.logAndSend(
                clientConnection: clientConnection, requestStart: requestStart,
                route: route, parsed: parsed, message: message
            )
        }

        timer = InactivityTimer(queue: processingQueue, interval: upstreamTimeout) {
            // ストリーム開始前なら 502、開始後なら接続クローズ。responseGuard で判定。
            if responseGuard.consume() {
                timer.stop()
                watchdog.cancel()
                upstream.cancel()
                self.logAndSend(
                    clientConnection: clientConnection, requestStart: requestStart,
                    route: route, parsed: parsed, message: "Upstream timed out (inactivity)"
                )
            } else {
                closeAfterStream(truncated: true)
            }
        }

        func readMore() {
            upstream.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
                guard let self else { upstream.cancel(); return }

                if let data, !data.isEmpty {
                    if firstByte {
                        firstByte = false
                        watchdog.cancel()
                        // 最初のバイトでストリーミング所有権を確定。取れなければ
                        // 既に別経路（タイムアウト等）が 502 を確定済み → 中断。
                        guard responseGuard.consume() else {
                            timer.stop(); upstream.cancel(); clientConnection.cancel()
                            return
                        }
                        statusLock.lock(); status = self.parseStatusCode(from: data); statusLock.unlock()
                    }
                    clientConnection.send(content: data, completion: .contentProcessed { sendError in
                        if sendError != nil {
                            closeAfterStream(truncated: true)
                            return
                        }
                        if isComplete || error != nil {
                            closeAfterStream(truncated: error != nil)
                            return
                        }
                        timer.reschedule() // 送信完了＝進捗あり → 期限を延長
                        readMore()
                    })
                    return
                }

                // データ無しのコールバック
                if isComplete || error != nil {
                    if firstByte {
                        // 1 バイトも受信せず終了 → エラー応答（まだヘッダ未送信）。
                        failBeforeStream(error.map { "Upstream error: \($0.localizedDescription)" } ?? "Empty upstream response")
                    } else {
                        closeAfterStream(truncated: error != nil)
                    }
                    return
                }

                readMore()
            }
        }

        timer.reschedule()
        readMore()
    }

    private func parseStatusCode(from responseData: Data) -> Int {
        guard let str = String(data: responseData.prefix(32), encoding: .utf8),
              str.hasPrefix("HTTP/") else { return 200 }
        // "HTTP/1.1 200 OK" → extract 200
        let parts = str.split(separator: " ", maxSplits: 2)
        if parts.count >= 2, let code = Int(parts[1]) {
            return code
        }
        return 200
    }

    private func logAndSend(clientConnection: NWConnection, requestStart: Date, route: ProxyRoute, parsed: HTTPRequestParser.ParsedRequest, message: String) {
        AppState.shared.proxyLogStore.append(ProxyLog(
            timestamp: requestStart, service: route.host,
            method: parsed.method, path: parsed.path,
            statusCode: 502, latency: Date().timeIntervalSince(requestStart), isError: true
        ))
        sendErrorResponse(connection: clientConnection, statusCode: 502, message: message)
    }

    // MARK: - Response Helpers

    private func sendResponse(connection: NWConnection, statusCode: Int, headers: [AnyHashable: Any], body: Data) {
        var responseLines = ["HTTP/1.1 \(statusCode) \(HTTPURLResponse.localizedString(forStatusCode: statusCode))"]

        // Forward response headers (filter out transfer-encoding for simplicity)
        for (key, value) in headers {
            let keyStr = "\(key)"
            let lower = keyStr.lowercased()
            if lower == "transfer-encoding" || lower == "content-length" { continue }
            responseLines.append("\(keyStr): \(value)")
        }

        responseLines.append("Content-Length: \(body.count)")
        responseLines.append("Connection: close")
        responseLines.append("")
        responseLines.append("")

        let headerData = responseLines.joined(separator: "\r\n").data(using: .utf8)!
        let fullResponse = headerData + body

        connection.send(content: fullResponse, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendErrorResponse(connection: NWConnection, statusCode: Int, message: String) {
        let json: [String: String] = ["error": message]
        let body = (try? JSONSerialization.data(withJSONObject: json)) ?? Data("{}".utf8)
        let headers: [AnyHashable: Any] = ["Content-Type": "application/json"]
        sendResponse(connection: connection, statusCode: statusCode, headers: headers, body: body)
    }
}
