import Foundation

/// 簡易 HTTP リクエストパーサー
/// プロキシが受け取る HTTP/1.1 リクエストをパースする
enum HTTPRequestParser {

    struct ParsedRequest {
        let method: String
        let path: String
        let host: String
        let headers: [(name: String, value: String)]
        let body: Data?
    }

    static func parse(_ requestString: String, body rawData: Data) -> ParsedRequest? {
        let lines = requestString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }

        // Parse request line: "POST /v1/messages HTTP/1.1"
        let parts = requestLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else { return nil }

        let method = String(parts[0])
        let path = String(parts[1])

        // Parse headers
        var headers: [(name: String, value: String)] = []
        var host = ""
        var contentLength = 0
        // headerEndIndex not needed - body extracted by separator search

        for i in 1..<lines.count {
            let line = lines[i]
            if line.isEmpty {
                break
            }

            if let colonIndex = line.firstIndex(of: ":") {
                let name = String(line[line.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                headers.append((name: name, value: value))

                if name.lowercased() == "host" {
                    host = value
                }
                if name.lowercased() == "content-length" {
                    contentLength = Int(value) ?? 0
                }
            }
        }

        // Extract body
        var body: Data?
        if contentLength > 0 {
            // Find the header/body separator in raw data
            let separator = Data("\r\n\r\n".utf8)
            if let range = rawData.range(of: separator) {
                let bodyStart = range.upperBound
                if bodyStart < rawData.endIndex {
                    body = rawData[bodyStart...]
                }
            }
        }

        return ParsedRequest(
            method: method,
            path: path,
            host: host,
            headers: headers,
            body: body
        )
    }
}
