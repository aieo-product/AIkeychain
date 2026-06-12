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

    private let breakerLock = NSLock()
    private var keychainUnavailableUntil: Date?

    init(keychainService: KeychainServiceProtocol = KeychainService.shared,
         keychainTimeout: TimeInterval = 3,
         upstreamTimeout: TimeInterval = 30,
         keychainCooldown: TimeInterval = 10) {
        self.keychainService = keychainService
        self.keychainTimeout = keychainTimeout
        self.upstreamTimeout = upstreamTimeout
        self.keychainCooldown = keychainCooldown
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

    private enum KeyReadResult {
        case success(String)
        case notFound
        case interactionRequired
        case timedOut
        case error(String)
    }

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

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            guard let self, let data else {
                connection.cancel()
                return
            }

            self.processRequest(data: data, connection: connection)
        }
    }

    /// Keychain 読み取りを非対話・タイムアウト付きで実行する。
    /// 非対話読み取りでも万一ブロックした場合に備え、別キューで実行して
    /// `keychainTimeout` で打ち切る（処理スレッドを占有させない）。
    private func readKeyWithTimeout(account: String) -> KeyReadResult {
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var outcome: KeyReadResult = .timedOut

        DispatchQueue.global(qos: .userInitiated).async { [keychainService] in
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

        // Connect to upstream via NWConnection (TLS)
        let tlsParams = NWParameters.tls
        let upstreamConnection = NWConnection(
            host: NWEndpoint.Host(route.host),
            port: .https,
            using: tlsParams
        )

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

    private func receiveUpstreamResponse(upstream: NWConnection, clientConnection: NWConnection, requestStart: Date, route: ProxyRoute, parsed: HTTPRequestParser.ParsedRequest, watchdog: DispatchWorkItem, responseGuard: OneShot) {
        // Receive all data from upstream then forward to client
        // Note: NWConnection の send は中間チャンクをフラッシュしないため、
        // ストリーミング転送ではなくバッファリング方式を使用
        var allData = Data()

        func readMore() {
            upstream.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
                if let data {
                    allData.append(data)
                }

                if isComplete || error != nil {
                    upstream.cancel()
                    watchdog.cancel()
                    guard responseGuard.consume() else { return }
                    let latency = Date().timeIntervalSince(requestStart)

                    if allData.isEmpty {
                        self?.logAndSend(
                            clientConnection: clientConnection, requestStart: requestStart,
                            route: route, parsed: parsed,
                            message: error.map { "Upstream error: \($0.localizedDescription)" } ?? "Empty upstream response"
                        )
                        return
                    }

                    let statusCode = self?.parseStatusCode(from: allData) ?? 200

                    AppState.shared.proxyLogStore.append(ProxyLog(
                        timestamp: requestStart, service: route.host,
                        method: parsed.method, path: parsed.path,
                        statusCode: statusCode, latency: latency,
                        isError: statusCode >= 400
                    ))
                    // requestCount は processRequest で既にインクリメント済み

                    clientConnection.send(content: allData, completion: .contentProcessed { _ in
                        clientConnection.cancel()
                    })
                    return
                }

                readMore()
            }
        }

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
