import Foundation
import Network
import Testing
@testable import AIkeychain

@Suite("ProxyRoute Tests")
struct ProxyRouteTests {

    @Test("Anthropic route found")
    func anthropicRoute() {
        let route = ProxyRoute.route(for: "api.anthropic.com")
        #expect(route != nil)
        #expect(route?.headerName == "x-api-key")
        #expect(route?.headerValuePrefix == "")
        #expect(route?.keychainAccount == "ANTHROPIC_API_KEY")
    }

    @Test("OpenAI route found")
    func openAIRoute() {
        let route = ProxyRoute.route(for: "api.openai.com")
        #expect(route != nil)
        #expect(route?.headerName == "Authorization")
        #expect(route?.headerValuePrefix == "Bearer ")
    }

    @Test("xAI route found")
    func xAIRoute() {
        let route = ProxyRoute.route(for: "api.x.ai")
        #expect(route != nil)
        #expect(route?.headerName == "Authorization")
    }

    @Test("Unknown host returns nil")
    func unknownHost() {
        let route = ProxyRoute.route(for: "example.com")
        #expect(route == nil)
    }

    @Test("Host with port still matches (port stripped)")
    func hostWithPort() {
        #expect(ProxyRoute.route(for: "api.anthropic.com:443") != nil)
    }

    @Test("Look-alike host does NOT match (exact match, not contains)")
    func lookAlikeHostRejected() {
        // issue #96: substring matching let attacker-controlled hosts match.
        #expect(ProxyRoute.route(for: "api.anthropic.com.attacker.test") == nil)
        #expect(ProxyRoute.route(for: "evil-api.anthropic.com") == nil)
        #expect(ProxyRoute.route(for: "notapi.openai.com") == nil)
    }
}

@Suite("HTTPRequestParser Tests")
struct HTTPRequestParserTests {

    @Test("Parse simple GET request")
    func parseGet() {
        let raw = "GET /v1/models HTTP/1.1\r\nHost: api.anthropic.com\r\nAccept: application/json\r\n\r\n"
        let data = Data(raw.utf8)
        let parsed = HTTPRequestParser.parse(raw, body: data)

        #expect(parsed != nil)
        #expect(parsed?.method == "GET")
        #expect(parsed?.path == "/v1/models")
        #expect(parsed?.host == "api.anthropic.com")
    }

    @Test("Parse POST request with body")
    func parsePost() {
        let body = "{\"model\":\"claude-sonnet-4-20250514\"}"
        let raw = "POST /v1/messages HTTP/1.1\r\nHost: api.anthropic.com\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\n\r\n\(body)"
        let data = Data(raw.utf8)
        let parsed = HTTPRequestParser.parse(raw, body: data)

        #expect(parsed != nil)
        #expect(parsed?.method == "POST")
        #expect(parsed?.path == "/v1/messages")
        #expect(parsed?.body != nil)

        if let parsedBody = parsed?.body {
            let bodyString = String(data: parsedBody, encoding: .utf8)
            #expect(bodyString?.contains("claude-sonnet-4-20250514") == true)
        }
    }

    @Test("Parse extracts all headers")
    func parseHeaders() {
        let raw = "GET / HTTP/1.1\r\nHost: api.anthropic.com\r\nAccept: */*\r\nUser-Agent: test\r\n\r\n"
        let data = Data(raw.utf8)
        let parsed = HTTPRequestParser.parse(raw, body: data)

        #expect(parsed?.headers.count == 3)
    }

    @Test("Invalid request returns nil")
    func invalidRequest() {
        let raw = "INVALID"
        let data = Data(raw.utf8)
        let parsed = HTTPRequestParser.parse(raw, body: data)
        // Should still parse the method at least, path might be missing
        // but won't crash
    }
}

@Suite("ProxyServer Tests")
struct ProxyServerTests {

    @Test("Server initializes with default port")
    func defaultPort() {
        let server = ProxyServer(keychainService: MockKeychainService())
        #expect(server.port == AppState.defaultPort)
        #expect(server.isRunning == false)
        #expect(server.requestCount == 0)
    }

    @Test("Server can start and stop")
    func startStop() throws {
        let server = ProxyServer(keychainService: MockKeychainService())
        try server.start()
        // State update is async via DispatchQueue.main
        // Verify the listener was created (start didn't throw)
        // and stop doesn't crash
        Thread.sleep(forTimeInterval: 0.3)
        server.stop()
        Thread.sleep(forTimeInterval: 0.3)
        // After stop, isRunning should eventually be false
        #expect(server.isRunning == false)
    }

    @Test("Starting twice does not crash")
    func doubleStart() throws {
        let server = ProxyServer(keychainService: MockKeychainService())
        try server.start()
        try server.start() // Should be no-op
        Thread.sleep(forTimeInterval: 0.3)
        server.stop()
    }
}

/// Keychain double whose non-interactive read blocks for a long time —
/// simulates the SecurityAgent consent prompt that caused the issue #96 hang.
final class BlockingKeychainService: KeychainServiceProtocol {
    let blockFor: TimeInterval
    init(blockFor: TimeInterval) { self.blockFor = blockFor }
    func save(value: String, for account: String) throws {}
    func retrieve(for account: String) throws -> String? { nil }
    func retrieveNoninteractive(for account: String) throws -> String? {
        Thread.sleep(forTimeInterval: blockFor)
        return "should-not-be-used"
    }
    func delete(for account: String) throws {}
    func exists(for account: String) -> Bool { false }
}

/// Keychain double that reports the read needs user interaction.
final class InteractionRequiredKeychainService: KeychainServiceProtocol {
    func save(value: String, for account: String) throws {}
    func retrieve(for account: String) throws -> String? { nil }
    func retrieveNoninteractive(for account: String) throws -> String? {
        throw KeychainError.interactionRequired
    }
    func delete(for account: String) throws {}
    func exists(for account: String) -> Bool { false }
}

/// Minimal raw-TCP HTTP client for talking to the local proxy in tests.
/// Returns (statusCode, elapsedSeconds). statusCode == -1 on connection failure.
enum TestHTTPClient {
    static func request(port: UInt16, host: String, token: String?, timeout: TimeInterval) -> (status: Int, elapsed: TimeInterval) {
        let start = Date()
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return (-1, 0) }
        defer { close(fd) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Foundation.connect(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connectResult == 0 else { return (-1, Date().timeIntervalSince(start)) }

        var req = "GET /v1/models HTTP/1.1\r\nHost: \(host)\r\n"
        if let token { req += "\(ProxyServer.tokenHeaderName): \(token)\r\n" }
        req += "Connection: close\r\n\r\n"
        _ = req.withCString { send(fd, $0, strlen($0), 0) }

        // bound read with a recv timeout
        var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var buf = [UInt8](repeating: 0, count: 4096)
        let n = recv(fd, &buf, buf.count, 0)
        let elapsed = Date().timeIntervalSince(start)
        guard n > 0, let resp = String(bytes: buf[0..<n], encoding: .utf8), resp.hasPrefix("HTTP/") else {
            return (-1, elapsed)
        }
        let parts = resp.split(separator: " ", maxSplits: 2)
        let status = parts.count >= 2 ? (Int(parts[1]) ?? -1) : -1
        return (status, elapsed)
    }
}

@Suite("Proxy Hang Regression Tests (issue #96)")
struct ProxyHangRegressionTests {

    /// Pick a high port unlikely to collide.
    private func testPort() -> UInt16 { UInt16.random(in: 19000...19900) }

    @Test("A blocked keychain read does NOT wedge other requests")
    func blockedReadDoesNotWedgeOthers() throws {
        let port = testPort()
        // keychain read blocks 10s, but our keychain timeout is 1s.
        let server = ProxyServer(
            keychainService: BlockingKeychainService(blockFor: 10),
            keychainTimeout: 1, upstreamTimeout: 5)
        server.port = port
        try server.start()
        defer { server.stop() }
        Thread.sleep(forTimeInterval: 0.4)
        let token = server.sessionToken

        // Fire a request that hits the (blocking) keychain read in the background.
        let blocker = Thread {
            _ = TestHTTPClient.request(port: port, host: "api.anthropic.com", token: token, timeout: 12)
        }
        blocker.start()
        Thread.sleep(forTimeInterval: 0.3) // let it reach the keychain read

        // Meanwhile, a no-token request must be rejected (403) essentially instantly,
        // proving the proxy is not wedged behind the blocked keychain read.
        let result = TestHTTPClient.request(port: port, host: "api.anthropic.com", token: nil, timeout: 3)
        #expect(result.status == 403)
        #expect(result.elapsed < 1.5)
    }

    @Test("A blocked keychain read returns a timeout error, never hangs forever")
    func blockedReadTimesOut() throws {
        let port = testPort()
        let server = ProxyServer(
            keychainService: BlockingKeychainService(blockFor: 30),
            keychainTimeout: 1, upstreamTimeout: 5)
        server.port = port
        try server.start()
        defer { server.stop() }
        Thread.sleep(forTimeInterval: 0.4)

        let result = TestHTTPClient.request(
            port: port, host: "api.anthropic.com", token: server.sessionToken, timeout: 8)
        // 504 Gateway Timeout, returned well before the 30s block would elapse.
        #expect(result.status == 504)
        #expect(result.elapsed < 4)
    }

    @Test("Keychain consent-required read returns 503 quickly, no hang")
    func interactionRequiredReturns503() throws {
        let port = testPort()
        let server = ProxyServer(
            keychainService: InteractionRequiredKeychainService(),
            keychainTimeout: 2, upstreamTimeout: 5)
        server.port = port
        try server.start()
        defer { server.stop() }
        Thread.sleep(forTimeInterval: 0.4)

        let result = TestHTTPClient.request(
            port: port, host: "api.anthropic.com", token: server.sessionToken, timeout: 5)
        #expect(result.status == 503)
        #expect(result.elapsed < 2)
    }

    @Test("Circuit breaker: after a timeout, subsequent reads fail fast without re-blocking")
    func circuitBreakerShortCircuits() throws {
        let port = testPort()
        // 10s block, 1s read timeout, 5s cooldown. First request times out (≈1s);
        // the next request during cooldown must return 503 almost instantly
        // (it must NOT spend another ~1s waiting on a fresh blocked read).
        let server = ProxyServer(
            keychainService: BlockingKeychainService(blockFor: 10),
            keychainTimeout: 1, upstreamTimeout: 5, keychainCooldown: 5)
        server.port = port
        try server.start()
        defer { server.stop() }
        Thread.sleep(forTimeInterval: 0.4)
        let token = server.sessionToken

        let first = TestHTTPClient.request(port: port, host: "api.anthropic.com", token: token, timeout: 5)
        #expect(first.status == 504)

        let second = TestHTTPClient.request(port: port, host: "api.anthropic.com", token: token, timeout: 5)
        #expect(second.status == 503)
        #expect(second.elapsed < 0.5) // short-circuited, not a fresh 1s block
    }

    @Test("Admission cap: concurrent burst during the first timeout window is bounded (fast 503)")
    func admissionCapBoundsConcurrentBurst() throws {
        let port = testPort()
        // Only 1 concurrent keychain read allowed; reads block 10s; read timeout 3s.
        // The first request occupies the single permit (blocked). A second request
        // arriving during the SAME timeout window — before the breaker has tripped —
        // must NOT spawn another blocked read; it gets 503 busy almost instantly.
        let server = ProxyServer(
            keychainService: BlockingKeychainService(blockFor: 10),
            keychainTimeout: 3, upstreamTimeout: 5, keychainCooldown: 10,
            maxConcurrentKeychainReads: 1)
        server.port = port
        try server.start()
        defer { server.stop() }
        Thread.sleep(forTimeInterval: 0.4)
        let token = server.sessionToken

        let blocker = Thread {
            _ = TestHTTPClient.request(port: port, host: "api.anthropic.com", token: token, timeout: 12)
        }
        blocker.start()
        Thread.sleep(forTimeInterval: 0.3) // first request now holds the single permit

        // Second request within the first read's 3s timeout window:
        let second = TestHTTPClient.request(port: port, host: "api.anthropic.com", token: token, timeout: 5)
        #expect(second.status == 503)
        #expect(second.elapsed < 1.0) // fast-failed by admission cap, not a fresh 3s block
    }

    @Test("Idle client connection is dropped after the inbound timeout")
    func idleConnectionDropped() throws {
        let port = testPort()
        let server = ProxyServer(
            keychainService: MockKeychainService(),
            keychainTimeout: 2, upstreamTimeout: 5, keychainCooldown: 10,
            maxConcurrentKeychainReads: 4, inboundTimeout: 1)
        server.port = port
        try server.start()
        defer { server.stop() }
        Thread.sleep(forTimeInterval: 0.4)

        // Connect but never send a request; the server must close the connection.
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        #expect(fd >= 0)
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connected = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Foundation.connect(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        #expect(connected == 0)

        // A blocking recv should return 0 (EOF) once the server cancels the idle connection.
        var tv = timeval(tv_sec: 4, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var buf = [UInt8](repeating: 0, count: 16)
        let start = Date()
        let n = recv(fd, &buf, buf.count, 0)
        let elapsed = Date().timeIntervalSince(start)
        #expect(n == 0)          // connection closed by server (EOF)
        #expect(elapsed < 3.5)   // around inboundTimeout (1s), not the recv timeout (4s)
    }

    @Test("Unknown host is rejected instantly without touching the keychain")
    func unknownHostInstant502() throws {
        let port = testPort()
        // Even with a blocking keychain, unknown-host must 502 immediately.
        let server = ProxyServer(
            keychainService: BlockingKeychainService(blockFor: 30),
            keychainTimeout: 2, upstreamTimeout: 5)
        server.port = port
        try server.start()
        defer { server.stop() }
        Thread.sleep(forTimeInterval: 0.4)

        let result = TestHTTPClient.request(
            port: port, host: "example.com", token: server.sessionToken, timeout: 3)
        #expect(result.status == 502)
        #expect(result.elapsed < 1.5)
    }
}

/// A local plaintext TCP "upstream" the proxy can be pointed at (via the
/// makeUpstream factory) so streaming/framing are testable without TLS or the network.
final class FakeUpstream {
    let port: UInt16
    private let listener: NWListener
    private let queue = DispatchQueue(label: "fake.upstream", attributes: .concurrent)

    init(port: UInt16, responder: @escaping (NWConnection, DispatchQueue) -> Void) throws {
        self.port = port
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port)!)
        listener = try NWListener(using: params)
        listener.newConnectionHandler = { [queue] conn in
            conn.start(queue: queue)
            responder(conn, queue)
        }
        listener.start(queue: queue)
    }

    func factory() -> (String) -> NWConnection {
        let p = port
        return { _ in
            NWConnection(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: p)!, using: .tcp)
        }
    }

    func stop() { listener.cancel() }
}

/// Raw-socket client with split-send and timed-recv, for streaming/framing tests.
final class RawClient {
    private let fd: Int32
    init?(port: UInt16) {
        fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let r = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { Foundation.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        if r != 0 { close(fd); return nil }
    }
    func send(_ s: String) { _ = s.withCString { Foundation.send(fd, $0, strlen($0), 0) } }
    /// recv with a timeout; returns whatever bytes arrived (may be empty on timeout/EOF).
    func recv(timeout: TimeInterval) -> Data {
        var tv = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - floor(timeout)) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var buf = [UInt8](repeating: 0, count: 8192)
        let n = Foundation.recv(fd, &buf, buf.count, 0)
        return n > 0 ? Data(buf[0..<n]) : Data()
    }
    func disconnect() { Foundation.close(fd) }
}

@Suite("Proxy HTTP Streaming & Framing Tests (issue #98)")
struct ProxyStreamingTests {
    private func port() -> UInt16 { UInt16.random(in: 20000...20900) }

    @Test("Upstream response is streamed to the client, not buffered until completion")
    func responseIsStreamed() throws {
        let upstreamPort = port()
        let proxyPort = port()
        // Upstream sends headers + first SSE event immediately, then waits 1.5s
        // before the second event and close. A buffering proxy would deliver
        // nothing until ~1.5s; a streaming proxy delivers event 1 right away.
        let upstream = try FakeUpstream(port: upstreamPort) { conn, queue in
            conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { _, _, _, _ in
                let head = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\n\r\ndata: 1\n\n"
                conn.send(content: Data(head.utf8), completion: .contentProcessed { _ in
                    queue.asyncAfter(deadline: .now() + 1.5) {
                        conn.send(content: Data("data: 2\n\n".utf8), completion: .contentProcessed { _ in
                            conn.cancel()
                        })
                    }
                })
            }
        }
        defer { upstream.stop() }

        let mock = MockKeychainService()
        try? mock.save(value: "test-key", for: "ANTHROPIC_API_KEY")
        let server = ProxyServer(keychainService: mock, upstreamTimeout: 10, makeUpstream: upstream.factory())
        server.port = proxyPort
        try server.start()
        defer { server.stop() }
        Thread.sleep(forTimeInterval: 0.4)

        let client = try #require(RawClient(port: proxyPort))
        defer { client.disconnect() }
        client.send("GET /v1/models HTTP/1.1\r\nHost: api.anthropic.com\r\n\(ProxyServer.tokenHeaderName): \(server.sessionToken)\r\n\r\n")

        // Within 0.8s (well before the upstream's 1.5s gap), we must already have
        // the status line and the first event — proof of streaming.
        let early = client.recv(timeout: 0.8)
        let earlyStr = String(data: early, encoding: .utf8) ?? ""
        #expect(earlyStr.contains("200"))
        #expect(earlyStr.contains("data: 1"))
        #expect(!earlyStr.contains("data: 2")) // second event hasn't been sent yet

        // Drain the rest.
        var rest = Data()
        for _ in 0..<5 {
            let chunk = client.recv(timeout: 2)
            if chunk.isEmpty { break }
            rest.append(chunk)
        }
        #expect((String(data: rest, encoding: .utf8) ?? "").contains("data: 2"))
    }

    @Test("Full request body is framed before forwarding (split header/body sends)")
    func requestBodyIsFullyFramed() throws {
        let upstreamPort = port()
        let proxyPort = port()
        let bodyLen = 5000 // larger than a typical single segment; sent in two writes
        // Upstream accumulates the request and reports how many body bytes it got.
        let upstream = try FakeUpstream(port: upstreamPort) { conn, _ in
            var buf = Data()
            func read() {
                conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, _ in
                    if let data { buf.append(data) }
                    if let r = buf.firstRange(of: Data("\r\n\r\n".utf8)) {
                        let cl = ProxyServer.parseContentLength(from: buf[buf.startIndex..<r.lowerBound])
                        let got = buf.distance(from: r.upperBound, to: buf.endIndex)
                        if got >= cl {
                            let resp = "HTTP/1.1 200 OK\r\nX-Body-Received: \(got)\r\nContent-Length: 0\r\n\r\n"
                            conn.send(content: Data(resp.utf8), completion: .contentProcessed { _ in conn.cancel() })
                            return
                        }
                    }
                    if isComplete { conn.cancel(); return }
                    read()
                }
            }
            read()
        }
        defer { upstream.stop() }

        let mock = MockKeychainService()
        try? mock.save(value: "test-key", for: "ANTHROPIC_API_KEY")
        let server = ProxyServer(keychainService: mock, upstreamTimeout: 10, inboundTimeout: 10, makeUpstream: upstream.factory())
        server.port = proxyPort
        try server.start()
        defer { server.stop() }
        Thread.sleep(forTimeInterval: 0.4)

        let client = try #require(RawClient(port: proxyPort))
        defer { client.disconnect() }
        // Send headers first, then the body after a delay — exercises framing.
        client.send("POST /v1/messages HTTP/1.1\r\nHost: api.anthropic.com\r\n\(ProxyServer.tokenHeaderName): \(server.sessionToken)\r\nContent-Length: \(bodyLen)\r\n\r\n")
        Thread.sleep(forTimeInterval: 0.3)
        client.send(String(repeating: "x", count: bodyLen))

        var resp = Data()
        for _ in 0..<5 {
            let chunk = client.recv(timeout: 3)
            if chunk.isEmpty { break }
            resp.append(chunk)
            if (String(data: resp, encoding: .utf8) ?? "").contains("\r\n\r\n") { break }
        }
        let respStr = String(data: resp, encoding: .utf8) ?? ""
        #expect(respStr.contains("X-Body-Received: \(bodyLen)")) // proxy forwarded the FULL body
    }

    @Test("parseContentLength reads the header case-insensitively")
    func parseContentLengthWorks() {
        let h = "POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 42\r\nAccept: */*"
        #expect(ProxyServer.parseContentLength(from: Data(h.utf8)) == 42)
        let h2 = "GET / HTTP/1.1\r\nhost: x"
        #expect(ProxyServer.parseContentLength(from: Data(h2.utf8)) == 0)
    }

    @Test("contentLengthField validates: absent/present/invalid (non-numeric, negative, conflicting)")
    func contentLengthValidation() {
        func field(_ s: String) -> ProxyServer.ContentLengthField {
            ProxyServer.contentLengthField(from: Data(s.utf8))
        }
        #expect(field("GET / HTTP/1.1\r\nHost: x") == .absent)
        #expect(field("POST / HTTP/1.1\r\nContent-Length: 10") == .present)
        #expect(field("POST / HTTP/1.1\r\nContent-Length: abc") == .invalid)
        #expect(field("POST / HTTP/1.1\r\nContent-Length: -5") == .invalid)
        #expect(field("POST / HTTP/1.1\r\nContent-Length: 10\r\nContent-Length: 20") == .invalid) // smuggling
        #expect(field("POST / HTTP/1.1\r\nContent-Length: 10\r\nContent-Length: 10") == .present) // duplicate-equal OK
    }

    @Test("Oversized request is rejected with 413")
    func oversizedRequestRejected() throws {
        let proxyPort = port()
        // 8KB cap (floor). Send a request larger than that.
        let server = ProxyServer(keychainService: MockKeychainService(),
                                 inboundTimeout: 10, maxRequestBytes: 8 * 1024)
        server.port = proxyPort
        try server.start()
        defer { server.stop() }
        Thread.sleep(forTimeInterval: 0.4)

        let client = try #require(RawClient(port: proxyPort))
        defer { client.disconnect() }
        let big = String(repeating: "y", count: 20_000)
        client.send("POST /v1/messages HTTP/1.1\r\nHost: api.anthropic.com\r\nContent-Length: 20000\r\n\r\n\(big)")
        let resp = String(data: client.recv(timeout: 3), encoding: .utf8) ?? ""
        #expect(resp.contains("413"))
    }

    @Test("Invalid (conflicting) Content-Length is rejected with 400")
    func invalidContentLengthRejected() throws {
        let proxyPort = port()
        let server = ProxyServer(keychainService: MockKeychainService(), inboundTimeout: 10)
        server.port = proxyPort
        try server.start()
        defer { server.stop() }
        Thread.sleep(forTimeInterval: 0.4)

        let client = try #require(RawClient(port: proxyPort))
        defer { client.disconnect() }
        client.send("POST /v1/messages HTTP/1.1\r\nHost: api.anthropic.com\r\nContent-Length: 5\r\nContent-Length: 9\r\n\r\nhello")
        let resp = String(data: client.recv(timeout: 3), encoding: .utf8) ?? ""
        #expect(resp.contains("400"))
    }

    @Test("Transfer-Encoding request is rejected with 400 (smuggling defense)")
    func transferEncodingRejected() throws {
        let proxyPort = port()
        let server = ProxyServer(keychainService: MockKeychainService(), inboundTimeout: 10)
        server.port = proxyPort
        try server.start()
        defer { server.stop() }
        Thread.sleep(forTimeInterval: 0.4)

        let client = try #require(RawClient(port: proxyPort))
        defer { client.disconnect() }
        client.send("POST /v1/messages HTTP/1.1\r\nHost: api.anthropic.com\r\n\(ProxyServer.tokenHeaderName): \(server.sessionToken)\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n")
        let resp = String(data: client.recv(timeout: 3), encoding: .utf8) ?? ""
        #expect(resp.contains("400"))
        #expect(resp.contains("Transfer-Encoding"))
    }
}

@Suite("Header Injection Security Tests")
struct HeaderInjectionSecurityTests {

    @Test("Route header value is correctly formatted for Anthropic")
    func anthropicHeaderFormat() {
        let route = ProxyRoute.route(for: "api.anthropic.com")!
        let apiKey = "sk-ant-test123"
        let headerValue = route.headerValuePrefix + apiKey
        #expect(headerValue == "sk-ant-test123") // No prefix for x-api-key
    }

    @Test("Route header value is correctly formatted for OpenAI")
    func openAIHeaderFormat() {
        let route = ProxyRoute.route(for: "api.openai.com")!
        let apiKey = "sk-test123"
        let headerValue = route.headerValuePrefix + apiKey
        #expect(headerValue == "Bearer sk-test123")
    }
}

@Suite("ProxyLog Tests")
struct ProxyLogTests {

    @Test("Log entry formats time correctly")
    func formattedTime() {
        let log = ProxyLog(
            timestamp: Date(), service: "api.anthropic.com",
            method: "POST", path: "/v1/messages",
            statusCode: 200, latency: 0.340, isError: false
        )
        #expect(!log.formattedTime.isEmpty)
        #expect(log.formattedLatency == "340ms")
        #expect(log.serviceDisplayName == "Anthropic")
    }

    @Test("Log entry detects errors")
    func errorDetection() {
        let errorLog = ProxyLog(
            timestamp: Date(), service: "api.openai.com",
            method: "POST", path: "/v1/chat/completions",
            statusCode: 429, latency: 0.050, isError: true
        )
        #expect(errorLog.isError == true)
        #expect(errorLog.serviceDisplayName == "OpenAI")
    }

    @Test("Log entry formats latency over 1 second")
    func latencyFormatting() {
        let slowLog = ProxyLog(
            timestamp: Date(), service: "api.x.ai",
            method: "POST", path: "/v1/chat/completions",
            statusCode: 200, latency: 2.5, isError: false
        )
        #expect(slowLog.formattedLatency == "2.5s")
        #expect(slowLog.serviceDisplayName == "xAI")
    }

    @Test("ProxyLogStore appends and limits entries")
    func storeAppendAndLimit() {
        let store = ProxyLogStore()
        let log = ProxyLog(
            timestamp: Date(), service: "api.anthropic.com",
            method: "POST", path: "/v1/messages",
            statusCode: 200, latency: 0.100, isError: false
        )
        store.logs.insert(log, at: 0)
        #expect(store.logs.count == 1)
        #expect(store.todayCount == 1)
        #expect(store.todayErrorCount == 0)
    }

    @Test("ProxyLogStore counts errors")
    func storeErrorCount() {
        let store = ProxyLogStore()
        store.logs.insert(ProxyLog(
            timestamp: Date(), service: "api.anthropic.com",
            method: "POST", path: "/v1/messages",
            statusCode: 500, latency: 0.050, isError: true
        ), at: 0)
        #expect(store.todayErrorCount == 1)
    }

    @Test("ProxyLogStore clear removes all logs")
    func storeClear() {
        let store = ProxyLogStore()
        store.logs.insert(ProxyLog(
            timestamp: Date(), service: "api.anthropic.com",
            method: "POST", path: "/v1/messages",
            statusCode: 200, latency: 0.100, isError: false
        ), at: 0)
        #expect(store.logs.count == 1)
        store.clear()
        #expect(store.logs.count == 0)
    }

    @Test("Log does not contain API key or request body")
    func securityCheck() {
        let log = ProxyLog(
            timestamp: Date(), service: "api.anthropic.com",
            method: "POST", path: "/v1/messages",
            statusCode: 200, latency: 0.340, isError: false
        )
        // ProxyLog has no fields for apiKey or body
        let mirror = Mirror(reflecting: log)
        let fieldNames = mirror.children.map { $0.label ?? "" }
        #expect(!fieldNames.contains("apiKey"))
        #expect(!fieldNames.contains("body"))
        #expect(!fieldNames.contains("requestBody"))
        #expect(!fieldNames.contains("authorization"))
    }
}
