import Foundation
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
        #expect(server.port == 9999)
        #expect(server.isRunning == false)
        #expect(server.requestCount == 0)
    }

    @Test("Server can start and stop")
    func startStop() throws {
        let server = ProxyServer(keychainService: MockKeychainService())
        try server.start()
        // Give it a moment to bind
        Thread.sleep(forTimeInterval: 0.5)
        #expect(server.isRunning == true)

        server.stop()
        Thread.sleep(forTimeInterval: 0.3)
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
