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
    var port: UInt16 = 9999
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
            sendErrorResponse(connection: connection, statusCode: 502, message: "No proxy route for host: \(parsed.host)")
            return
        }

        // Read API key from Keychain
        guard let apiKey = try? keychainService.retrieve(for: route.keychainAccount), !apiKey.isEmpty else {
            sendErrorResponse(connection: connection, statusCode: 401, message: "API key not found in Keychain for \(route.keychainAccount)")
            return
        }

        // Forward request with injected auth header
        forwardRequest(parsed: parsed, route: route, apiKey: apiKey, connection: connection)
    }

    private func forwardRequest(parsed: HTTPRequestParser.ParsedRequest, route: ProxyRoute, apiKey: String, connection: NWConnection) {
        // Build upstream URL
        guard let url = URL(string: "\(route.targetScheme)://\(route.host)\(parsed.path)") else {
            sendErrorResponse(connection: connection, statusCode: 500, message: "Invalid upstream URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = parsed.method
        request.timeoutInterval = 120

        // Copy original headers (except Host and auth headers)
        for (name, value) in parsed.headers {
            let lower = name.lowercased()
            if lower == "host" || lower == "authorization" || lower == "x-api-key" { continue }
            request.setValue(value, forHTTPHeaderField: name)
        }

        // Inject auth header from Keychain
        let headerValue = route.headerValuePrefix + apiKey
        request.setValue(headerValue, forHTTPHeaderField: route.headerName)

        // Set correct Host
        request.setValue(route.host, forHTTPHeaderField: "Host")

        // Set body if present
        if let body = parsed.body {
            request.httpBody = body
        }

        // Execute request
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            defer { connection.cancel() }

            if let error {
                self?.sendErrorResponse(connection: connection, statusCode: 502, message: "Upstream error: \(error.localizedDescription)")
                return
            }

            guard let httpResponse = response as? HTTPURLResponse, let data else {
                self?.sendErrorResponse(connection: connection, statusCode: 502, message: "Invalid upstream response")
                return
            }

            DispatchQueue.main.async {
                self?.requestCount += 1
            }

            // Build HTTP response
            self?.sendResponse(connection: connection, statusCode: httpResponse.statusCode, headers: httpResponse.allHeaderFields, body: data)
        }
        task.resume()
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
