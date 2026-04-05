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

    private var listener: NWListener?
    private let keychainService: KeychainServiceProtocol
    private let queue = DispatchQueue(label: "com.aieo.aikeychain.proxy", qos: .userInitiated)

    init(keychainService: KeychainServiceProtocol = KeychainService.shared) {
        self.keychainService = keychainService
    }

    func start() throws {
        guard !isRunning else { return }

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
        connection.start(queue: queue)

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self, let data else {
                connection.cancel()
                return
            }

            self.processRequest(data: data, connection: connection)
        }
    }

    private func processRequest(data: Data, connection: NWConnection) {
        guard let requestString = String(data: data, encoding: .utf8) else {
            sendErrorResponse(connection: connection, statusCode: 400, message: "Invalid request")
            return
        }

        // Parse HTTP request
        guard let parsed = HTTPRequestParser.parse(requestString, body: data) else {
            sendErrorResponse(connection: connection, statusCode: 400, message: "Failed to parse HTTP request")
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

        // Read API key from Keychain
        guard let apiKey = try? keychainService.retrieve(for: route.keychainAccount), !apiKey.isEmpty else {
            AppState.shared.proxyLogStore.append(ProxyLog(
                timestamp: Date(), service: route.host,
                method: parsed.method, path: parsed.path,
                statusCode: 401, latency: 0, isError: true
            ))
            sendErrorResponse(connection: connection, statusCode: 401, message: "API key not found in Keychain for \(route.keychainAccount)")
            return
        }

        // Forward request with injected auth header
        forwardRequest(parsed: parsed, route: route, apiKey: apiKey, clientConnection: connection)
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

        // Copy original headers (except Host and auth headers)
        for (name, value) in parsed.headers {
            let lower = name.lowercased()
            if lower == "host" || lower == "authorization" || lower == "x-api-key" { continue }
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

        upstreamConnection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                // Connection established - send the request
                upstreamConnection.send(content: requestData, completion: .contentProcessed { sendError in
                    if let sendError {
                        self?.logAndRespondError(
                            clientConnection: clientConnection, requestStart: requestStart,
                            route: route, parsed: parsed, latency: Date().timeIntervalSince(requestStart),
                            message: "Upstream send error: \(sendError.localizedDescription)"
                        )
                        upstreamConnection.cancel()
                        return
                    }
                    // Receive upstream response
                    self?.receiveUpstreamResponse(
                        upstream: upstreamConnection, clientConnection: clientConnection,
                        requestStart: requestStart, route: route, parsed: parsed
                    )
                })

            case .failed(let error):
                self?.logAndRespondError(
                    clientConnection: clientConnection, requestStart: requestStart,
                    route: route, parsed: parsed, latency: Date().timeIntervalSince(requestStart),
                    message: "Upstream connection failed: \(error.localizedDescription)"
                )
                upstreamConnection.cancel()

            default:
                break
            }
        }

        upstreamConnection.start(queue: queue)
    }

    private func receiveUpstreamResponse(upstream: NWConnection, clientConnection: NWConnection, requestStart: Date, route: ProxyRoute, parsed: HTTPRequestParser.ParsedRequest) {
        // Receive all data from upstream
        var allData = Data()

        func readMore() {
            upstream.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
                if let data {
                    allData.append(data)
                }

                if isComplete || error != nil {
                    // All data received - forward to client
                    upstream.cancel()
                    let latency = Date().timeIntervalSince(requestStart)

                    if allData.isEmpty {
                        self?.logAndRespondError(
                            clientConnection: clientConnection, requestStart: requestStart,
                            route: route, parsed: parsed, latency: latency,
                            message: "Empty upstream response"
                        )
                        return
                    }

                    // Parse status code from response for logging
                    let statusCode = self?.parseStatusCode(from: allData) ?? 200

                    AppState.shared.proxyLogStore.append(ProxyLog(
                        timestamp: requestStart, service: route.host,
                        method: parsed.method, path: parsed.path,
                        statusCode: statusCode, latency: latency,
                        isError: statusCode >= 400
                    ))
                    DispatchQueue.main.async { self?.requestCount += 1 }

                    // Forward raw HTTP response to client
                    clientConnection.send(content: allData, completion: .contentProcessed { _ in
                        clientConnection.cancel()
                    })
                    return
                }

                // More data to read
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

    private func logAndRespondError(clientConnection: NWConnection, requestStart: Date, route: ProxyRoute, parsed: HTTPRequestParser.ParsedRequest, latency: TimeInterval, message: String) {
        AppState.shared.proxyLogStore.append(ProxyLog(
            timestamp: requestStart, service: route.host,
            method: parsed.method, path: parsed.path,
            statusCode: 502, latency: latency, isError: true
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
        let body = "{\"error\":\"\(message)\"}".data(using: .utf8)!
        let headers: [AnyHashable: Any] = ["Content-Type": "application/json"]
        sendResponse(connection: connection, statusCode: statusCode, headers: headers, body: body)
    }
}
