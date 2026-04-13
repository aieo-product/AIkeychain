import SwiftUI

struct SetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isConfigured = SetupManager.isConfigured()
    @State private var setupComplete = false
    @State private var errorMessage: String?
    @State private var portText = "\(AppState.shared.proxyPort)"

    private var currentPort: UInt16 {
        AppState.shared.proxyPort
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header
            Image(systemName: "shield.checkered")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.accentGradient)

            Text("Secure Proxy Setup")
                .font(AppFonts.pageTitle)

            Text("AI KeyChain protects your API keys by injecting them\nvia a local proxy — they never appear in environment variables.")
                .font(AppFonts.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Divider()
                .padding(.horizontal, 40)

            // What will be configured
            VStack(alignment: .leading, spacing: 12) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Local Proxy Server")
                            .font(.system(size: 14, weight: .medium))
                        Text("localhost:\(currentPort) — auto-starts with the app")
                            .font(AppFonts.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "server.rack")
                        .foregroundStyle(AppColors.cloudBlue)
                }

                // Port selector
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Proxy Port")
                            .font(.system(size: 14, weight: .medium))
                        HStack(spacing: 8) {
                            TextField("Port", text: $portText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                                .onSubmit { applyPort() }
                            Button("Apply") { applyPort() }
                                .controlSize(.small)
                            Text("(default: \(AppState.defaultPort))")
                                .font(AppFonts.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                } icon: {
                    Image(systemName: "number")
                        .foregroundStyle(AppColors.gitOrange)
                }

                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Shell Configuration")
                            .font(.system(size: 14, weight: .medium))
                        Text(L10n.s(ja: "プロキシ起動中のみ BASE_URL を自動設定（停止時は自動削除）", en: "Auto-sets BASE_URL while proxy is running (auto-removed when stopped)"))
                            .font(AppFonts.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "terminal")
                        .foregroundStyle(AppColors.commGreen)
                }

                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keychain Integration")
                            .font(.system(size: 14, weight: .medium))
                        Text("API keys stay in macOS Keychain — never in env or files")
                            .font(AppFonts.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "key.fill")
                        .foregroundStyle(AppColors.aiPurple)
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

            // Code preview
            VStack(alignment: .leading, spacing: 4) {
                Text("Added to ~/.zshrc:")
                    .font(AppFonts.badge)
                    .foregroundStyle(.secondary)
                Text("[ -f ~/.aikeychain_proxy ] && source ~/.aikeychain_proxy")
                    .font(AppFonts.code)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(.textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

            if let error = errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(AppFonts.caption)
            }

            Spacer()

            // Actions
            HStack {
                Button("Skip") {
                    dismiss()
                }

                Spacer()

                if setupComplete || isConfigured {
                    Label("Configured", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(AppColors.configured)

                    Button("Done") {
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Enable Secure Proxy") {
                        enableProxy()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.top, 8)
        }
        .padding(30)
        .frame(width: 540, height: 580)
    }

    private func applyPort() {
        guard let value = UInt16(portText), value >= 1024 else {
            errorMessage = L10n.s(ja: "ポート番号は 1024〜65535 の範囲で指定してください", en: "Port number must be between 1024 and 65535")
            return
        }
        errorMessage = nil
        AppState.shared.changePort(to: value)
    }

    private func enableProxy() {
        do {
            try SetupManager.configure()
            isConfigured = true
            setupComplete = true
            errorMessage = nil
        } catch {
            errorMessage = "Failed to configure: \(error.localizedDescription)"
        }
    }
}
