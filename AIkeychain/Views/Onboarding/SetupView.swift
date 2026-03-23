import SwiftUI

struct SetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isConfigured = SetupManager.isConfigured()
    @State private var setupComplete = false
    @State private var errorMessage: String?

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
                        Text("localhost:9999 — auto-starts with the app")
                            .font(AppFonts.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "server.rack")
                        .foregroundStyle(AppColors.cloudBlue)
                }

                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Shell Configuration")
                            .font(.system(size: 14, weight: .medium))
                        Text(".zshrc に BASE_URL を追記（API キーは書き込みません）")
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
                Text("export ANTHROPIC_BASE_URL=http://localhost:9999")
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
        .frame(width: 500, height: 560)
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
