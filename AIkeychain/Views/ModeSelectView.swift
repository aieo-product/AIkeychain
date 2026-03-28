import SwiftUI

/// キー管理モード選択画面
/// Standard（通常Keychain）か Proxy かをユーザーが選択する
struct ModeSelectView: View {
    @Environment(\.dismiss) private var dismiss
    let appState: AppState
    @State private var selectedMode: KeyManagementMode
    @State private var showProxyConsent = false

    init(appState: AppState = .shared) {
        self.appState = appState
        self._selectedMode = State(initialValue: appState.keyManagementMode)
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Image(systemName: "switch.2")
                    .font(.system(size: 28))
                    .foregroundStyle(AppColors.accentGradient)
                VStack(alignment: .leading) {
                    Text("Key Management Mode")
                        .font(AppFonts.sectionTitle)
                    Text("API キーの管理方式を選択")
                        .font(AppFonts.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }

            Divider()

            // Mode cards
            VStack(spacing: 12) {
                ModeCard(
                    mode: .standard,
                    isSelected: selectedMode == .standard,
                    title: "Standard",
                    subtitle: "通常 Keychain 参照",
                    icon: "key.fill",
                    color: AppColors.commGreen,
                    features: [
                        "API キーを .zshrc で直接 export",
                        "プロキシ不要 — シンプルで安定",
                        "SSH 経由では Keychain 承認が必要な場合あり",
                    ]
                ) {
                    selectedMode = .standard
                }

                ModeCard(
                    mode: .proxy,
                    isSelected: selectedMode == .proxy,
                    title: "Proxy",
                    subtitle: "プロキシ経由（上級者向け）",
                    icon: "shield.checkered",
                    color: AppColors.aiPurple,
                    features: [
                        "env に API キーが露出しない",
                        "SSH / Tailscale 経由でも Keychain 承認不要",
                        "AI KeyChain アプリの常時起動が必須",
                    ]
                ) {
                    if appState.hasProxyConsent {
                        selectedMode = .proxy
                    } else {
                        showProxyConsent = true
                    }
                }
            }

            // Current mode indicator
            if appState.keyManagementMode != selectedMode {
                Label("適用ボタンでモードを切り替えます", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            }

            Spacer()

            // Actions
            HStack {
                if appState.isProxyMode {
                    Button("Recovery Guide") {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            NotificationCenter.default.post(name: .showRecovery, object: nil)
                        }
                    }
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Cancel") { dismiss() }

                Button("Apply") {
                    appState.switchMode(to: selectedMode)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.keyManagementMode == selectedMode)
            }
        }
        .padding(24)
        .frame(width: 520, height: 560)
        .sheet(isPresented: $showProxyConsent) {
            ProxyConsentView {
                appState.hasProxyConsent = true
                selectedMode = .proxy
            }
        }
    }
}

// MARK: - Mode Card

private struct ModeCard: View {
    let mode: KeyManagementMode
    let isSelected: Bool
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let features: [String]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(color)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(title)
                            .font(.system(size: 15, weight: .semibold))
                        Text("— \(subtitle)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    ForEach(features, id: \.self) { feature in
                        HStack(alignment: .top, spacing: 4) {
                            Text("*")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                            Text(feature)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? color : Color.gray.opacity(0.3))
            }
            .padding(14)
            .background(
                isSelected ? color.opacity(0.06) : Color.clear,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? color.opacity(0.4) : Color.gray.opacity(0.15), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Proxy Consent View

struct ProxyConsentView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var agreed = false
    let onConsent: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)

            Text("Proxy Mode — 利用上の注意")
                .font(.system(size: 16, weight: .bold))

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ConsentSection(icon: "exclamationmark.circle", color: .orange, items: [
                        "Proxy モードでは AI KeyChain アプリが常時起動している必要があります",
                        "アプリが停止すると AI API (Claude, OpenAI 等) への接続が一時的にできなくなります",
                        "PC のシャットダウンや強制終了時にも同様の影響があります",
                    ])

                    Divider()

                    Text("復旧方法")
                        .font(.system(size: 13, weight: .semibold))

                    ConsentSection(icon: "wrench", color: .blue, items: [
                        "AI KeyChain アプリを再起動すればプロキシが自動復旧します",
                        "急ぎの場合は Standard モードに切り替えてください",
                        "最終手段: ~/.aikeychain_proxy を手動削除すれば直接 API 接続に戻ります",
                    ])

                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("即時復旧コマンド（ターミナルで実行）:")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("rm -f ~/.aikeychain_proxy && exec $SHELL")
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(height: 280)

            Toggle(isOn: $agreed) {
                Text("上記の注意事項を理解し、自己責任で利用します")
                    .font(.system(size: 12))
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("同意して有効化") {
                    onConsent()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!agreed)
            }
        }
        .padding(20)
        .frame(width: 460, height: 520)
    }
}

private struct ConsentSection: View {
    let icon: String
    let color: Color
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 11))
                        .foregroundStyle(color)
                        .frame(width: 16)
                    Text(item)
                        .font(.system(size: 12))
                }
            }
        }
    }
}
