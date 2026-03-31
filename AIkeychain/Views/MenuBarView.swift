import SwiftUI

extension Notification.Name {
    static let showOnboarding = Notification.Name("showOnboarding")
    static let showCleanup = Notification.Name("showCleanup")
    static let showModeSelect = Notification.Name("showModeSelect")
    static let showRecovery = Notification.Name("showRecovery")
}

struct MenuBarView: View {
    let appState: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var portText: String = ""
    @State private var showPortEditor = false
    @State private var portError: String?

    private var modeIcon: String {
        switch appState.keyManagementMode {
        case .standard: "key.fill"
        case .secretReference: "link.badge.plus"
        case .proxy: "shield.checkered"
        }
    }

    private var modeColor: Color {
        switch appState.keyManagementMode {
        case .standard: AppColors.commGreen
        case .secretReference: AppColors.cloudBlue
        case .proxy: AppColors.aiPurple
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Mode indicator
            HStack(spacing: 6) {
                Image(systemName: modeIcon)
                    .font(.system(size: 10))
                    .foregroundStyle(modeColor)
                Text("Mode: \(appState.keyManagementMode.displayName)")
                    .font(.system(size: 11))
            }

            // Proxy status (only in proxy mode)
            if appState.isProxyMode {
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
            }

            Divider()

            // Mode switch
            Button("Change Mode...") {
                openWindow(id: "main")
                NSApplication.shared.activate(ignoringOtherApps: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NotificationCenter.default.post(name: .showModeSelect, object: nil)
                }
            }

            // Proxy controls (only in proxy mode)
            if appState.isProxyMode {
                if appState.proxyServer.isRunning {
                    Button("Stop Proxy") {
                        appState.stopProxy()
                    }
                } else {
                    Button("Start Proxy") {
                        appState.startProxyIfNeeded()
                    }
                }

                // Port setting
                Button("Change Port...") {
                    portText = "\(appState.proxyPort)"
                    portError = nil
                    showPortEditor.toggle()
                }

                if showPortEditor {
                    HStack(spacing: 4) {
                        TextField("Port", text: $portText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                            .onSubmit { applyPort() }
                        Button("Apply") { applyPort() }
                            .controlSize(.small)
                    }
                    .padding(.leading, 4)

                    if let error = portError {
                        Text(error)
                            .font(.system(size: 10))
                            .foregroundStyle(.red)
                            .padding(.leading, 4)
                    }
                }

                Button("Recovery Guide...") {
                    openWindow(id: "main")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        NotificationCenter.default.post(name: .showRecovery, object: nil)
                    }
                }
            }

            Divider()

            // Open main window
            Button("Open KeyChain...") {
                openWindow(id: "main")
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("k", modifiers: [.command])

            Button("Open Keychain Access") {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Keychain Access.app"))
            }

            Divider()

            Toggle("Launch at Login", isOn: Binding(
                get: { appState.launchAtLogin },
                set: { appState.launchAtLogin = $0 }
            ))

            Divider()

            Button("Shell Cleanup...") {
                openWindow(id: "main")
                NSApplication.shared.activate(ignoringOtherApps: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NotificationCenter.default.post(name: .showCleanup, object: nil)
                }
            }

            Button("Show Tutorial") {
                openWindow(id: "main")
                NSApplication.shared.activate(ignoringOtherApps: true)
                // Notify MainView to show onboarding
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NotificationCenter.default.post(name: .showOnboarding, object: nil)
                }
            }

            Divider()

            Button("Quit") {
                appState.stopProxy()
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
        .padding(4)
    }

    private func applyPort() {
        guard let value = UInt16(portText), value >= 1024 else {
            portError = "1024〜65535 の範囲で指定"
            return
        }
        portError = nil
        showPortEditor = false
        appState.changePort(to: value)
    }
}
