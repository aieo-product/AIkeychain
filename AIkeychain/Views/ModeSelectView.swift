import SwiftUI

/// キー管理モード選択画面
/// Standard（通常Keychain）か Proxy かをユーザーが選択する
struct ModeSelectView: View {
    @Environment(\.dismiss) private var dismiss
    let appState: AppState
    @State private var selectedMode: KeyManagementMode
    @State private var showProxyConsent = false
    @State private var showComparison = false

    init(appState: AppState = .shared) {
        self.appState = appState
        self._selectedMode = State(initialValue: appState.keyManagementMode)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "switch.2")
                    .font(.system(size: 28))
                    .foregroundStyle(AppColors.accentGradient)
                VStack(alignment: .leading) {
                    Text("Key Management Mode")
                        .font(AppFonts.sectionTitle)
                    Text(L10n.s(ja: "API キーの管理方式を選択", en: "Select API key management method"))
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
            .padding(.bottom, 16)

            Divider()

            // Scrollable content
            ScrollView {
                VStack(spacing: 20) {
                    // Mode cards
                    VStack(spacing: 12) {
                        ModeCard(
                            mode: .standard,
                            isSelected: selectedMode == .standard,
                            title: "Standard",
                            subtitle: L10n.s(ja: "通常 Keychain 参照", en: "Standard Keychain"),
                            icon: "key.fill",
                            color: AppColors.commGreen,
                            features: [
                                L10n.s(ja: "API キーを .zshrc で直接 export", en: "Export API keys directly in .zshrc"),
                                L10n.s(ja: "プロキシ不要 — シンプルで安定", en: "No proxy needed — simple and stable"),
                                L10n.s(ja: "SSH 経由では Keychain 承認が必要な場合あり", en: "Keychain authorization may be required via SSH"),
                            ]
                        ) {
                            selectedMode = .standard
                        }

                        ModeCard(
                            mode: .secretReference,
                            isSelected: selectedMode == .secretReference,
                            title: "Secret Reference",
                            subtitle: L10n.s(ja: "keychain:// 参照（1Password 方式）", en: "keychain:// reference (1Password style)"),
                            icon: "link.badge.plus",
                            color: AppColors.cloudBlue,
                            features: [
                                L10n.s(ja: "env にはパス情報のみ — キー値が露出しない", en: "Only path info in env — key values are never exposed"),
                                L10n.s(ja: "akc run で実行時に Keychain から解決", en: "Resolved from Keychain at runtime via akc run"),
                                L10n.s(ja: "アプリ常時起動は不要", en: "App does not need to run constantly"),
                            ]
                        ) {
                            selectedMode = .secretReference
                        }

                        ModeCard(
                            mode: .proxy,
                            isSelected: selectedMode == .proxy,
                            title: "Proxy",
                            subtitle: L10n.s(ja: "プロキシ経由（上級者向け）", en: "Via proxy (advanced)"),
                            icon: "shield.checkered",
                            color: AppColors.aiPurple,
                            features: [
                                L10n.s(ja: "env に API キーが露出しない", en: "API keys are never exposed in env"),
                                L10n.s(ja: "SSH / Tailscale 経由でも Keychain 承認不要", en: "No Keychain authorization needed via SSH / Tailscale"),
                                L10n.s(ja: "AI KeyChain アプリの常時起動が必須", en: "AI KeyChain app must be running at all times"),
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
                        Label(L10n.s(ja: "適用ボタンでモードを切り替えます", en: "Press Apply to switch modes"), systemImage: "arrow.triangle.2.circlepath")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                    }

                    // Mode comparison detail
                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            withAnimation { showComparison.toggle() }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: showComparison ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                                Text(L10n.s(ja: "モード比較の詳細", en: "Mode Comparison Details"))
                                    .font(.system(size: 13))
                                Spacer()
                            }
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if showComparison {
                            ModeComparisonView()
                                .padding(.top, 4)
                        }
                    }
                }
                .padding(.top, 16)
            }

            Divider()

            // Actions (fixed at bottom)
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
            .padding(.top, 16)
        }
        .padding(24)
        .frame(width: 540, height: 740)
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
            .contentShape(Rectangle())
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

            Text(L10n.s(ja: "Proxy Mode — 利用上の注意", en: "Proxy Mode — Important Notice"))
                .font(.system(size: 16, weight: .bold))

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ConsentSection(icon: "exclamationmark.circle", color: .orange, items: [
                        L10n.s(ja: "Proxy モードでは AI KeyChain アプリが常時起動している必要があります", en: "Proxy mode requires the AI KeyChain app to be running at all times"),
                        L10n.s(ja: "アプリが停止すると AI API (Claude, OpenAI 等) への接続が一時的にできなくなります", en: "If the app stops, connections to AI APIs (Claude, OpenAI, etc.) will be temporarily unavailable"),
                        L10n.s(ja: "PC のシャットダウンや強制終了時にも同様の影響があります", en: "The same applies during PC shutdown or force quit"),
                    ])

                    Divider()

                    Text(L10n.s(ja: "復旧方法", en: "Recovery Steps"))
                        .font(.system(size: 13, weight: .semibold))

                    ConsentSection(icon: "wrench", color: .blue, items: [
                        L10n.s(ja: "AI KeyChain アプリを再起動すればプロキシが自動復旧します", en: "Restart the AI KeyChain app to automatically restore the proxy"),
                        L10n.s(ja: "急ぎの場合は Standard モードに切り替えてください", en: "Switch to Standard mode if you need immediate access"),
                        L10n.s(ja: "最終手段: ~/.aikeychain_proxy を手動削除すれば直接 API 接続に戻ります", en: "Last resort: manually delete ~/.aikeychain_proxy to restore direct API access"),
                    ])

                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.s(ja: "即時復旧コマンド（ターミナルで実行）:", en: "Immediate recovery command (run in Terminal):"))
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
                Text(L10n.s(ja: "上記の注意事項を理解し、自己責任で利用します", en: "I understand the above and accept responsibility"))
                    .font(.system(size: 12))
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button(L10n.s(ja: "同意して有効化", en: "Agree and Enable")) {
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
