import SwiftUI

/// プロキシモードの復旧ガイド
/// API 接続ができなくなった場合の復旧手順を表示する
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
                        Text("Recovery Guide")
                            .font(AppFonts.sectionTitle)
                        Text("プロキシモード復旧ガイド")
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
                    Text("Proxy: \(appState.proxyServer.isRunning ? "Running (Port \(appState.proxyPort))" : "Stopped")")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text("Mode: \(appState.keyManagementMode.displayName)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

                // Recovery options
                VStack(alignment: .leading, spacing: 16) {

                    RecoveryOption(
                        step: "1",
                        title: "AI KeyChain を再起動",
                        description: "最も簡単な方法です。アプリを再起動すればプロキシが自動復旧します。",
                        command: nil,
                        severity: .info
                    )

                    RecoveryOption(
                        step: "2",
                        title: "Standard モードに切り替え",
                        description: "プロキシを使わず、従来の Keychain 直接参照に戻します。",
                        command: nil,
                        severity: .info,
                        action: appState.isProxyMode ? ("Switch to Standard", {
                            AppState.shared.switchMode(to: .standard)
                        }) : nil
                    )

                    RecoveryOption(
                        step: "3",
                        title: "設定ファイルを手動削除（即時復旧）",
                        description: "ターミナルで以下を実行すると、プロキシ設定が即座に解除され、直接 API 接続に戻ります。",
                        command: "rm -f ~/.aikeychain_proxy && exec $SHELL",
                        severity: .warning
                    )

                    RecoveryOption(
                        step: "4",
                        title: ".zshrc のフックを削除（完全除去）",
                        description: "プロキシモードを完全に無効化し、.zshrc からフックも削除します。",
                        command: """
                        # フックを削除
                        sed -i '' '/aikeychain_proxy/d' ~/.zshrc
                        sed -i '' '/AI KeyChain.*proxy env/d' ~/.zshrc

                        # 設定ファイルも削除
                        rm -f ~/.aikeychain_proxy

                        # シェルを再読み込み
                        exec $SHELL
                        """,
                        severity: .destructive
                    )
                }

                Divider()

                // FAQ
                VStack(alignment: .leading, spacing: 10) {
                    Text("FAQ")
                        .font(.system(size: 14, weight: .semibold))

                    FAQItem(
                        q: "PC を強制シャットダウンしたら Claude が使えなくなった",
                        a: "AI KeyChain アプリを起動してください。プロキシが自動起動し復旧します。急ぎの場合は Step 3 のコマンドを実行してください。"
                    )
                    FAQItem(
                        q: "ECONNREFUSED エラーが出る",
                        a: "プロキシが停止しています。AI KeyChain を起動するか、Step 3 で設定ファイルを削除してください。"
                    )
                    FAQItem(
                        q: "元の方式に完全に戻したい",
                        a: "Step 2 で Standard モードに切り替えてください。.zshrc のフックも削除したい場合は Step 4 を実行してください。"
                    )
                    FAQItem(
                        q: "akc run で「keychain:// が解決できない」と出る",
                        a: "該当するキーが Keychain に登録されているか確認してください。akc run --dry-run で解決可能なキーを確認できます。"
                    )
                    FAQItem(
                        q: "Secret Reference モードで SDK が認証エラーになる",
                        a: "akc run -- <command> でラップして実行してください。直接実行すると keychain:// の文字列がそのまま送信されます。"
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
                        .help("Copy")
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
