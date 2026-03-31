import SwiftUI

/// プロキシリクエストログの Activity 表示
struct ActivityView: View {
    private var logStore: ProxyLogStore { .shared }
    private var appState: AppState { .shared }

    var body: some View {
        VStack(spacing: 0) {
            // サマリヘッダ
            HStack(spacing: 16) {
                Label("Today: \(logStore.todayCount) requests", systemImage: "arrow.up.arrow.down")
                if logStore.todayErrorCount > 0 {
                    Label("Errors: \(logStore.todayErrorCount)", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else {
                    Label("Errors: 0", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                Spacer()
                if !logStore.logs.isEmpty {
                    Button("Clear") {
                        logStore.clear()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11))
                }
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            if !appState.isProxyMode {
                ContentUnavailableView {
                    Label("Proxy Mode Disabled", systemImage: "shield.slash")
                } description: {
                    Text("Activity logging is available in Proxy mode.\nSwitch to Proxy mode to see request logs.")
                }
            } else if logStore.logs.isEmpty {
                ContentUnavailableView {
                    Label("No Activity", systemImage: "tray")
                } description: {
                    Text("Proxy request logs will appear here.\nLogs are stored in memory only and cleared on restart.")
                }
            } else {
                // ログテーブル
                Table(logStore.logs) {
                    TableColumn("Time") { log in
                        Text(log.formattedTime)
                            .font(.system(size: 11, design: .monospaced))
                    }
                    .width(min: 60, ideal: 70)

                    TableColumn("Service") { log in
                        Text(log.serviceDisplayName)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .width(min: 70, ideal: 80)

                    TableColumn("Endpoint") { log in
                        Text("\(log.method) \(log.path)")
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                    }
                    .width(min: 150, ideal: 250)

                    TableColumn("Status") { log in
                        Text("\(log.statusCode)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(log.isError ? .red : .green)
                    }
                    .width(min: 45, ideal: 50)

                    TableColumn("Latency") { log in
                        Text(log.formattedLatency)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 50, ideal: 60)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
    }
}
