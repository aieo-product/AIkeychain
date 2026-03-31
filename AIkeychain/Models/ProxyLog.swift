import Foundation

/// プロキシを通過したリクエストのログエントリ
/// セキュリティ要件: トークン値・リクエストボディは含めない
struct ProxyLog: Identifiable {
    let id = UUID()
    let timestamp: Date
    let service: String       // "Anthropic", "OpenAI", "xAI"
    let method: String        // GET, POST, etc.
    let path: String          // /v1/messages, etc.
    let statusCode: Int
    let latency: TimeInterval // seconds
    let isError: Bool

    var serviceDisplayName: String {
        switch service {
        case "api.anthropic.com": return "Anthropic"
        case "api.openai.com":   return "OpenAI"
        case "api.x.ai":        return "xAI"
        default:                 return service
        }
    }

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: timestamp)
    }

    var formattedLatency: String {
        if latency < 1 {
            return "\(Int(latency * 1000))ms"
        } else {
            return String(format: "%.1fs", latency)
        }
    }
}

/// プロキシログのメモリ内ストア
/// ディスクには永続化しない（セキュリティ要件）
@Observable
final class ProxyLogStore {
    static let shared = ProxyLogStore()

    private(set) var logs: [ProxyLog] = []

    /// 本日のリクエスト数
    var todayCount: Int {
        let cal = Calendar.current
        return logs.filter { cal.isDateInToday($0.timestamp) }.count
    }

    /// 本日のエラー数
    var todayErrorCount: Int {
        let cal = Calendar.current
        return logs.filter { cal.isDateInToday($0.timestamp) && $0.isError }.count
    }

    func append(_ log: ProxyLog) {
        DispatchQueue.main.async {
            self.logs.insert(log, at: 0) // 新しい順
            // メモリ保護: 最大500件
            if self.logs.count > 500 {
                self.logs = Array(self.logs.prefix(500))
            }
        }
    }

    func clear() {
        DispatchQueue.main.async {
            self.logs.removeAll()
        }
    }
}
