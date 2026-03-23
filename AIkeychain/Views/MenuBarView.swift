import SwiftUI

struct MenuBarView: View {
    let appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Proxy status
            HStack(spacing: 6) {
                Circle()
                    .fill(appState.proxyServer.isRunning ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text("Proxy: \(appState.proxyServer.isRunning ? "Running" : "Stopped")")
            }

            Text("Port: \(appState.proxyServer.port)")
                .foregroundStyle(.secondary)
            Text("Requests: \(appState.proxyServer.requestCount)")
                .foregroundStyle(.secondary)

            Divider()

            // Proxy control
            if appState.proxyServer.isRunning {
                Button("Stop Proxy") {
                    appState.proxyServer.stop()
                }
            } else {
                Button("Start Proxy") {
                    appState.startProxyIfNeeded()
                }
            }

            Divider()

            // Open main window
            Button("Open KeyChain...") {
                openWindow(id: "main")
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("k", modifiers: [.command])

            Divider()

            Toggle("Launch at Login", isOn: Binding(
                get: { appState.launchAtLogin },
                set: { appState.launchAtLogin = $0 }
            ))

            Divider()

            Button("Quit") {
                appState.proxyServer.stop()
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
        .padding(4)
    }
}
