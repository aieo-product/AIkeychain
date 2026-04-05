import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack {
                    Image(systemName: "key.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(AppColors.accentGradient)
                    VStack(alignment: .leading) {
                        Text("AI KeyChain")
                            .font(AppFonts.sectionTitle)
                        Text(L10n.t("help_title"))
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

                // Overview
                HelpSection(title: L10n.t("help_overview"), icon: "info.circle") {
                    Text(L10n.s(
                        ja: "AI KeyChain は AI API キーを macOS Keychain で安全に管理し、ローカルプロキシ経由で認証を行うアプリです。環境変数に API キーを露出させることなく、AI ツールを利用できます。",
                        en: "AI KeyChain securely manages AI API keys in macOS Keychain and authenticates via local proxy. Use AI tools without exposing API keys in environment variables."
                    ))
                }

                // How it works
                HelpSection(title: L10n.t("help_mechanism"), icon: "gearshape.2") {
                    VStack(alignment: .leading, spacing: 8) {
                        HelpStep(num: "1", text: L10n.s(
                            ja: "API キーは macOS Keychain に暗号化保存されます",
                            en: "API keys are encrypted and stored in macOS Keychain"))
                        HelpStep(num: "2", text: L10n.s(
                            ja: "アプリ起動時にローカルプロキシ (localhost:\(AppState.shared.proxyPort)) が自動起動します",
                            en: "A local proxy (localhost:\(AppState.shared.proxyPort)) auto-starts with the app"))
                        HelpStep(num: "3", text: L10n.s(
                            ja: "AI ツール (claude 等) のリクエストをプロキシが中継します",
                            en: "The proxy intercepts requests from AI tools (claude, etc.)"))
                        HelpStep(num: "4", text: L10n.s(
                            ja: "プロキシが Keychain から API キーを読み取り、認証ヘッダを注入します",
                            en: "The proxy reads API keys from Keychain and injects auth headers"))
                        HelpStep(num: "5", text: L10n.s(
                            ja: "AI ツールの env には API キーが存在しないため、流出リスクがありません",
                            en: "No API keys exist in AI tool env, eliminating leakage risk"))
                    }
                }

                // Key Management
                HelpSection(title: L10n.s(ja: "キーの管理", en: "Key Management"), icon: "key") {
                    VStack(alignment: .leading, spacing: 8) {
                        HelpItem(title: L10n.s(ja: "キーの登録", en: "Register Keys"),
                                 desc: L10n.s(ja: "サイドバーでカテゴリを選択 → 「Add Key」ボタン → サービスを選択してトークンを入力 → 「Save to Keychain」",
                                              en: "Select category in sidebar → \"Add Key\" → Choose service and enter token → \"Save to Keychain\""))
                        HelpItem(title: L10n.s(ja: "キーの編集", en: "Edit Keys"),
                                 desc: L10n.s(ja: "キーをダブルクリック、または右クリック → Edit",
                                              en: "Double-click a key, or right-click → Edit"))
                        HelpItem(title: L10n.s(ja: "キーの削除", en: "Delete Keys"),
                                 desc: L10n.s(ja: "編集画面で「Delete」ボタン → 確認ダイアログで「Delete」",
                                              en: "Click \"Delete\" in the editor → Confirm in the dialog"))
                        HelpItem(title: L10n.s(ja: "値のコピー", en: "Copy Value"),
                                 desc: L10n.s(ja: "キーを右クリック → Copy Value（30秒後に自動でクリップボードクリア）",
                                              en: "Right-click a key → Copy Value (clipboard auto-clears after 30s)"))
                    }
                }

                // Menu Bar
                HelpSection(title: L10n.s(ja: "メニューバー", en: "Menu Bar"), icon: "menubar.rectangle") {
                    VStack(alignment: .leading, spacing: 8) {
                        HelpItem(title: L10n.s(ja: "ステータス確認", en: "Status Check"),
                                 desc: L10n.s(ja: "メニューバーの鍵アイコンでプロキシの動作状況を確認",
                                              en: "Check proxy status via the key icon in the menu bar"))
                        HelpItem(title: L10n.s(ja: "プロキシ制御", en: "Proxy Control"),
                                 desc: L10n.s(ja: "Start / Stop でプロキシの起動・停止",
                                              en: "Start / Stop to control the proxy"))
                        HelpItem(title: L10n.s(ja: "常駐動作", en: "Background Operation"),
                                 desc: L10n.s(ja: "ウィンドウを閉じてもプロキシはバックグラウンドで動作します",
                                              en: "Proxy keeps running in the background even when the window is closed"))
                        HelpItem(title: L10n.s(ja: "自動起動", en: "Auto-start"),
                                 desc: L10n.s(ja: "Launch at Login を有効にするとログイン時に自動起動",
                                              en: "Enable Launch at Login to auto-start on login"))
                    }
                }

                // Modes
                HelpSection(title: L10n.s(ja: "管理モード", en: "Management Modes"), icon: "switch.2") {
                    ModeComparisonView()
                }

                // Export
                HelpSection(title: L10n.t("help_export"), icon: "square.and.arrow.up") {
                    VStack(alignment: .leading, spacing: 8) {
                        HelpItem(title: L10n.s(ja: ".zshrc 形式", en: ".zshrc Format"),
                                 desc: L10n.s(ja: "Keychain 参照の export 文を生成（トークンの値は含まれません）",
                                              en: "Generate export statements with Keychain references (no token values)"))
                        HelpItem(title: L10n.s(ja: ".zshrc (Secret Reference)", en: ".zshrc (Secret Reference)"),
                                 desc: L10n.s(ja: "keychain:// 参照の export 文を生成。akc run と組み合わせて使用。",
                                              en: "Generate keychain:// reference exports. Use with akc run."))
                        HelpItem(title: L10n.s(ja: ".env 形式", en: ".env Format"),
                                 desc: L10n.s(ja: "環境変数名のテンプレートを生成（値は <VALUE> プレースホルダー）",
                                              en: "Generate env variable template (values are <VALUE> placeholders)"))
                    }
                }

                // Troubleshooting
                HelpSection(title: L10n.s(ja: "トラブルシューティング", en: "Troubleshooting"), icon: "wrench") {
                    VStack(alignment: .leading, spacing: 8) {
                        HelpItem(title: L10n.s(ja: "ECONNREFUSED エラーが出る", en: "ECONNREFUSED Error"),
                                 desc: L10n.s(ja: "Proxy モードで AI KeyChain アプリが停止しています。アプリを再起動するか、Standard モードに切り替えてください。即時復旧: rm -f ~/.aikeychain_proxy && exec $SHELL",
                                              en: "AI KeyChain app is stopped in Proxy mode. Restart the app or switch to Standard mode. Instant fix: rm -f ~/.aikeychain_proxy && exec $SHELL"))
                        HelpItem(title: L10n.s(ja: "プロキシが起動しない", en: "Proxy Won't Start"),
                                 desc: L10n.s(ja: "設定ポートが他のアプリに使用されていないか確認してください。lsof -i :\(AppState.shared.proxyPort) で確認できます。",
                                              en: "Check if the port is used by another app. Verify with lsof -i :\(AppState.shared.proxyPort)"))
                        HelpItem(title: L10n.s(ja: "API 認証エラー", en: "API Auth Error"),
                                 desc: L10n.s(ja: "該当するキーが Keychain に登録されているか確認してください。キーの横に ✅ が表示されていれば登録済みです。",
                                              en: "Verify the key is registered in Keychain. A ✅ next to the key means it's configured."))
                        HelpItem(title: L10n.s(ja: "モードを切り替えたい", en: "Switch Modes"),
                                 desc: L10n.s(ja: "メニューバー → Change Mode、またはツールバー → Help → Change Mode から切り替えできます。",
                                              en: "Switch via Menu Bar → Change Mode, or Toolbar → Help → Change Mode."))
                        HelpItem(title: L10n.s(ja: "オンボーディングを再表示", en: "Show Tutorial Again"),
                                 desc: L10n.s(ja: "メニューバー → Help → Show Tutorial から再度チュートリアルを表示できます。",
                                              en: "Go to Menu Bar → Help → Show Tutorial to replay the onboarding."))
                    }
                }

                // Keyboard Shortcuts
                HelpSection(title: L10n.t("help_shortcuts"), icon: "keyboard") {
                    VStack(alignment: .leading, spacing: 6) {
                        ShortcutRow(keys: "⌘ K", action: L10n.s(ja: "メイン画面を開く", en: "Open main window"))
                        ShortcutRow(keys: "⌘ N", action: L10n.s(ja: "新しいキーを追加", en: "Add new key"))
                        ShortcutRow(keys: "⌘ Q", action: L10n.s(ja: "アプリを終了", en: "Quit app"))
                    }
                }

                Divider()

                // Show tutorial button
                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        NotificationCenter.default.post(name: .showOnboarding, object: nil)
                    }
                } label: {
                    Label(L10n.t("help_show_tutorial"), systemImage: "play.circle")
                }
                .buttonStyle(.bordered)
            }
            .padding(24)
        }
        .frame(width: 580, height: 640)
    }
}

// MARK: - Mode Comparison View

struct ModeComparisonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Mode descriptions
            VStack(alignment: .leading, spacing: 10) {
                ModeRow(
                    icon: "key.fill", color: AppColors.commGreen,
                    name: "Standard", security: 1,
                    desc: L10n.s(ja: ".zshrc で Keychain から直接 export。シンプルだが env にキー値が見える。",
                                 en: "Direct export from Keychain via .zshrc. Simple but key values visible in env.")
                )
                ModeRow(
                    icon: "link.badge.plus", color: AppColors.cloudBlue,
                    name: "Secret Reference", security: 2,
                    desc: L10n.s(ja: "env に keychain:// 参照のみ。akc run で実行時に解決。1Password op:// と同等。",
                                 en: "Only keychain:// references in env. Resolved at runtime by akc run. Equivalent to 1Password op://.")
                )
                ModeRow(
                    icon: "shield.checkered", color: AppColors.aiPurple,
                    name: "Proxy", security: 3,
                    desc: L10n.s(ja: "プロキシが認証ヘッダを注入。キーがどのプロセスにも渡らない最も安全な方式。",
                                 en: "Proxy injects auth headers. Keys never reach any user process — the most secure mode.")
                )
            }

            Divider()

            // Key reach comparison
            Text(L10n.s(ja: "キーの到達範囲", en: "Key Reach Scope"))
                .font(.system(size: 12, weight: .semibold))

            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    Text("").frame(width: 120, alignment: .leading)
                    Text("Standard").font(.system(size: 10, weight: .semibold)).foregroundStyle(AppColors.commGreen)
                    Text("Secret Ref").font(.system(size: 10, weight: .semibold)).foregroundStyle(AppColors.cloudBlue)
                    Text("Proxy").font(.system(size: 10, weight: .semibold)).foregroundStyle(AppColors.aiPurple)
                }
                Divider()
                ComparisonRow(label: L10n.s(ja: "親プロセスの env", en: "Parent env"),
                              values: L10n.isJa ? ["キー値あり", "パスのみ", "キーなし"] : ["Key values", "Path only", "No keys"],
                              danger: [true, false, false])
                ComparisonRow(label: L10n.s(ja: "子プロセスのメモリ", en: "Child memory"),
                              values: L10n.isJa ? ["キーあり", "キーあり", "キーなし"] : ["Has keys", "Has keys", "No keys"],
                              danger: [true, true, false])
                ComparisonRow(label: L10n.s(ja: "プロセスダンプ漏洩", en: "Dump leakage"),
                              values: L10n.isJa ? ["リスクあり", "リスクあり", "リスクなし"] : ["Risk", "Risk", "Safe"],
                              danger: [true, true, false])
                ComparisonRow(label: L10n.s(ja: "アプリ常時起動", en: "App always-on"),
                              values: L10n.isJa ? ["不要", "不要", "必要"] : ["No", "No", "Required"],
                              danger: [false, false, true])
                ComparisonRow(label: L10n.s(ja: "SDK 直接実行", en: "Direct SDK exec"),
                              values: L10n.isJa ? ["可能", "akc run 必要", "可能"] : ["OK", "Needs akc run", "OK"],
                              danger: [false, true, false])
            }
            .font(.system(size: 11))

            Divider()

            // Visual explanation
            Text(L10n.s(ja: "Secret Reference vs Proxy の核心的な違い", en: "Key Difference: Secret Reference vs Proxy"))
                .font(.system(size: 12, weight: .semibold))

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 11))
                    Text(L10n.s(
                        ja: "Secret Reference: akc run が子プロセスの env にキー値を注入するため、子プロセスのメモリにはキーが存在する。プロセスダンプで漏洩する可能性がある。",
                        en: "Secret Reference: akc run injects key values into the child process env, so keys exist in child process memory. They could leak via process dump."
                    ))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(AppColors.aiPurple)
                        .font(.system(size: 11))
                    Text(L10n.s(
                        ja: "Proxy: キーはプロキシプロセス内部でのみ読み取られ、HTTP ヘッダとして外部に送信される。ユーザーのプロセスにキーが一切渡らない。",
                        en: "Proxy: Keys are read only within the proxy process and sent as HTTP headers. No keys ever reach the user's process."
                    ))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct ModeRow: View {
    let icon: String
    let color: Color
    let name: String
    let security: Int
    let desc: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.system(size: 12, weight: .semibold))
                    HStack(spacing: 1) {
                        ForEach(0..<3, id: \.self) { i in
                            Image(systemName: i < security ? "star.fill" : "star")
                                .font(.system(size: 8))
                                .foregroundStyle(i < security ? color : Color.gray.opacity(0.3))
                        }
                    }
                }
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ComparisonRow: View {
    let label: String
    let values: [String]
    let danger: [Bool]

    var body: some View {
        GridRow {
            Text(label)
                .font(.system(size: 11))
                .frame(width: 120, alignment: .leading)
            ForEach(Array(values.enumerated()), id: \.offset) { i, val in
                Text(val)
                    .font(.system(size: 10))
                    .foregroundStyle(danger[i] ? .orange : AppColors.configured)
            }
        }
    }
}

// MARK: - Help Components

private struct HelpSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.system(size: 15, weight: .semibold))
            content
                .font(.system(size: 13))
                .padding(.leading, 4)
        }
    }
}

private struct HelpItem: View {
    let title: String
    let desc: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
            Text(desc)
                .font(AppFonts.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct HelpStep: View {
    let num: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(num)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(AppColors.aiPurple, in: Circle())
            Text(text)
                .font(.system(size: 13))
        }
    }
}

private struct ShortcutRow: View {
    let keys: String
    let action: String

    var body: some View {
        HStack {
            Text(keys)
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
            Text(action)
                .font(.system(size: 13))
        }
    }
}
