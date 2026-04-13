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
                Text(L10n.t("menubar_mode").replacingOccurrences(of: "%@", with: appState.keyManagementMode.displayName))
                    .font(.system(size: 11))
            }

            // Proxy status (only in proxy mode)
            if appState.isProxyMode {
                HStack(spacing: 6) {
                    Circle()
                        .fill(appState.proxyServer.isRunning ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(appState.proxyServer.isRunning ? L10n.t("menubar_proxy_running") : L10n.t("menubar_proxy_stopped"))
                }

                Text(L10n.t("menubar_port").replacingOccurrences(of: "%@", with: "\(appState.proxyServer.port)"))
                    .foregroundStyle(.secondary)
                Text(L10n.t("menubar_requests").replacingOccurrences(of: "%@", with: "\(appState.proxyServer.requestCount)"))
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Mode switch
            Button(L10n.t("menubar_change_mode")) {
                openWindow(id: "main")
                NSApplication.shared.activate(ignoringOtherApps: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NotificationCenter.default.post(name: .showModeSelect, object: nil)
                }
            }

            // Proxy controls (only in proxy mode)
            if appState.isProxyMode {
                if appState.proxyServer.isRunning {
                    Button(L10n.t("menubar_stop_proxy")) {
                        appState.stopProxy()
                    }
                } else {
                    Button(L10n.t("menubar_start_proxy")) {
                        appState.startProxyIfNeeded()
                    }
                }

                // Port setting
                Button(L10n.t("menubar_change_port")) {
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
                        Button(L10n.t("apply")) { applyPort() }
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

                Button(L10n.t("menubar_recovery")) {
                    openWindow(id: "main")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        NotificationCenter.default.post(name: .showRecovery, object: nil)
                    }
                }
            }

            Divider()

            // Open main window
            Button(L10n.t("menubar_open_keychain")) {
                openWindow(id: "main")
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("k", modifiers: [.command])

            Button(L10n.t("menubar_open_keychain_access")) {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Keychain Access.app"))
            }

            Divider()

            Toggle(L10n.t("menubar_launch_at_login"), isOn: Binding(
                get: { appState.launchAtLogin },
                set: { appState.launchAtLogin = $0 }
            ))

            // Language switcher
            Menu(L10n.t("menubar_language")) {
                ForEach(AppLanguage.allCases) { lang in
                    Button {
                        appState.appLanguage = lang
                    } label: {
                        HStack {
                            Text("\(lang.flag) \(lang.displayName)")
                            if appState.appLanguage == lang {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Divider()

            Button(L10n.t("menubar_shell_cleanup")) {
                openWindow(id: "main")
                NSApplication.shared.activate(ignoringOtherApps: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NotificationCenter.default.post(name: .showCleanup, object: nil)
                }
            }

            Button(L10n.t("menubar_show_tutorial")) {
                openWindow(id: "main")
                NSApplication.shared.activate(ignoringOtherApps: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NotificationCenter.default.post(name: .showOnboarding, object: nil)
                }
            }

            Divider()

            Button(L10n.t("menubar_quit")) {
                appState.stopProxy()
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
        .padding(4)
    }

    private func applyPort() {
        guard let value = UInt16(portText), value >= 1024 else {
            portError = L10n.t("shell_port_error")
            return
        }
        portError = nil
        showPortEditor = false
        appState.changePort(to: value)
    }
}
