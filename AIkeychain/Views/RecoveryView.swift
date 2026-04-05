import SwiftUI

/// プロキシモードの復旧ガイド
struct RecoveryView: View {
    @Environment(\.dismiss) private var dismiss
    let appState: AppState

    init(appState: AppState = .shared) {
        self.appState = appState
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    Image(systemName: "lifepreserver")
                        .font(.system(size: 28))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading) {
                        Text(L10n.t("recovery_title"))
                            .font(AppFonts.sectionTitle)
                        Text(L10n.t("recovery_subtitle"))
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

                // Current status
                HStack(spacing: 10) {
                    Circle()
                        .fill(appState.proxyServer.isRunning ? Color.green : Color.red)
                        .frame(width: 10, height: 10)
                    Text(appState.proxyServer.isRunning
                         ? L10n.t("recovery_running").replacingOccurrences(of: "%@", with: "\(appState.proxyPort)")
                         : L10n.t("recovery_stopped"))
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text(L10n.t("recovery_mode").replacingOccurrences(of: "%@", with: appState.keyManagementMode.displayName))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

                // Recovery options
                VStack(alignment: .leading, spacing: 16) {
                    RecoveryOption(
                        step: "1",
                        title: L10n.t("recovery_restart_title"),
                        description: L10n.t("recovery_restart_desc"),
                        command: nil,
                        severity: .info
                    )

                    RecoveryOption(
                        step: "2",
                        title: L10n.t("recovery_switch_title"),
                        description: L10n.t("recovery_switch_desc"),
                        command: nil,
                        severity: .info,
                        action: appState.isProxyMode ? (L10n.s(ja: "Standard に切替", en: "Switch to Standard"), {
                            AppState.shared.switchMode(to: .standard)
                        }) : nil
                    )

                    RecoveryOption(
                        step: "3",
                        title: L10n.t("recovery_manual_title"),
                        description: L10n.t("recovery_manual_desc"),
                        command: "rm -f ~/.aikeychain_proxy && exec $SHELL",
                        severity: .warning
                    )

                    RecoveryOption(
                        step: "4",
                        title: L10n.t("recovery_zshrc_title"),
                        description: L10n.s(ja: "プロキシモードを完全に無効化し、.zshrc からフックも削除します。",
                                            en: "Completely disable proxy mode and remove the hook from .zshrc."),
                        command: """
                        # \(L10n.s(ja: "フックを削除", en: "Remove hook"))
                        sed -i '' '/aikeychain_proxy/d' ~/.zshrc
                        sed -i '' '/AI KeyChain.*proxy env/d' ~/.zshrc

                        # \(L10n.s(ja: "設定ファイルも削除", en: "Remove config file"))
                        rm -f ~/.aikeychain_proxy

                        # \(L10n.s(ja: "シェルを再読み込み", en: "Reload shell"))
                        exec $SHELL
                        """,
                        severity: .destructive
                    )
                }

                Divider()

                // FAQ
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.t("recovery_faq"))
                        .font(.system(size: 14, weight: .semibold))

                    FAQItem(
                        q: L10n.s(ja: "PC を強制シャットダウンしたら Claude が使えなくなった",
                                  en: "Claude stopped working after a forced shutdown"),
                        a: L10n.s(ja: "AI KeyChain アプリを起動してください。プロキシが自動起動し復旧します。急ぎの場合は Step 3 のコマンドを実行してください。",
                                  en: "Launch AI KeyChain. The proxy will auto-start and recover. For urgent cases, run the Step 3 command.")
                    )
                    FAQItem(
                        q: L10n.s(ja: "ECONNREFUSED エラーが出る",
                                  en: "Getting ECONNREFUSED error"),
                        a: L10n.s(ja: "プロキシが停止しています。AI KeyChain を起動するか、Step 3 で設定ファイルを削除してください。",
                                  en: "The proxy is stopped. Launch AI KeyChain or delete the config file via Step 3.")
                    )
                    FAQItem(
                        q: L10n.s(ja: "元の方式に完全に戻したい",
                                  en: "Want to revert completely to the original method"),
                        a: L10n.s(ja: "Step 2 で Standard モードに切り替えてください。.zshrc のフックも削除したい場合は Step 4 を実行してください。",
                                  en: "Switch to Standard mode in Step 2. To also remove the .zshrc hook, run Step 4.")
                    )
                    FAQItem(
                        q: L10n.s(ja: "akc run で「keychain:// が解決できない」と出る",
                                  en: "akc run says \"keychain:// cannot be resolved\""),
                        a: L10n.s(ja: "該当するキーが Keychain に登録されているか確認してください。akc run --dry-run で解決可能なキーを確認できます。",
                                  en: "Verify the key is registered in Keychain. Use akc run --dry-run to check which keys can be resolved.")
                    )
                    FAQItem(
                        q: L10n.s(ja: "Secret Reference モードで SDK が認証エラーになる",
                                  en: "SDK auth error in Secret Reference mode"),
                        a: L10n.s(ja: "akc run -- <command> でラップして実行してください。直接実行すると keychain:// の文字列がそのまま送信されます。",
                                  en: "Wrap your command with akc run -- <command>. Running directly sends the keychain:// string as-is.")
                    )
                }
            }
            .padding(24)
        }
        .frame(width: 580, height: 640)
    }
}

// MARK: - Components

private struct RecoveryOption: View {
    enum Severity { case info, warning, destructive }

    let step: String
    let title: String
    let description: String
    let command: String?
    let severity: Severity
    var action: (String, () -> Void)? = nil

    private var color: Color {
        switch severity {
        case .info: .blue
        case .warning: .orange
        case .destructive: .red
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(step)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(color, in: Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))

                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                if let command {
                    HStack(alignment: .top) {
                        Text(command)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(command, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help(L10n.t("copy"))
                    }
                    .padding(8)
                    .background(Color(.textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                }

                if let (label, handler) = action {
                    Button(label, action: handler)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
    }
}

private struct FAQItem: View {
    let q: String
    let a: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Q: \(q)")
                .font(.system(size: 12, weight: .medium))
            Text("A: \(a)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}
