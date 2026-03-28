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
                        Text("User Manual")
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
                HelpSection(title: "概要", icon: "info.circle") {
                    Text("AI KeyChain は AI API キーを macOS Keychain で安全に管理し、ローカルプロキシ経由で認証を行うアプリです。環境変数に API キーを露出させることなく、AI ツールを利用できます。")
                }

                // How it works
                HelpSection(title: "仕組み", icon: "gearshape.2") {
                    VStack(alignment: .leading, spacing: 8) {
                        HelpStep(num: "1", text: "API キーは macOS Keychain に暗号化保存されます")
                        HelpStep(num: "2", text: "アプリ起動時にローカルプロキシ (localhost:\(AppState.shared.proxyPort)) が自動起動します")
                        HelpStep(num: "3", text: "AI ツール (claude 等) のリクエストをプロキシが中継します")
                        HelpStep(num: "4", text: "プロキシが Keychain から API キーを読み取り、認証ヘッダを注入します")
                        HelpStep(num: "5", text: "AI ツールの env には API キーが存在しないため、流出リスクがありません")
                    }
                }

                // Key Management
                HelpSection(title: "キーの管理", icon: "key") {
                    VStack(alignment: .leading, spacing: 8) {
                        HelpItem(title: "キーの登録", desc: "サイドバーでカテゴリを選択 → 「Add Key」ボタン → サービスを選択してトークンを入力 → 「Save to Keychain」")
                        HelpItem(title: "キーの編集", desc: "キーをダブルクリック、または右クリック → Edit")
                        HelpItem(title: "キーの削除", desc: "編集画面で「Delete」ボタン → 確認ダイアログで「Delete」")
                        HelpItem(title: "値のコピー", desc: "キーを右クリック → Copy Value（30秒後に自動でクリップボードクリア）")
                    }
                }

                // Menu Bar
                HelpSection(title: "メニューバー", icon: "menubar.rectangle") {
                    VStack(alignment: .leading, spacing: 8) {
                        HelpItem(title: "ステータス確認", desc: "メニューバーの鍵アイコンでプロキシの動作状況を確認")
                        HelpItem(title: "プロキシ制御", desc: "Start / Stop でプロキシの起動・停止")
                        HelpItem(title: "常駐動作", desc: "ウィンドウを閉じてもプロキシはバックグラウンドで動作します")
                        HelpItem(title: "自動起動", desc: "Launch at Login を有効にするとログイン時に自動起動")
                    }
                }

                // Export
                HelpSection(title: "エクスポート", icon: "square.and.arrow.up") {
                    VStack(alignment: .leading, spacing: 8) {
                        HelpItem(title: ".zshrc 形式", desc: "Keychain 参照の export 文を生成（トークンの値は含まれません）")
                        HelpItem(title: ".env 形式", desc: "環境変数名のテンプレートを生成（値は <VALUE> プレースホルダー）")
                    }
                }

                // Troubleshooting
                HelpSection(title: "トラブルシューティング", icon: "wrench") {
                    VStack(alignment: .leading, spacing: 8) {
                        HelpItem(title: "ECONNREFUSED エラーが出る",
                                 desc: "Proxy モードで AI KeyChain アプリが停止しています。アプリを再起動するか、Standard モードに切り替えてください。即時復旧: rm -f ~/.aikeychain_proxy && exec $SHELL")
                        HelpItem(title: "プロキシが起動しない",
                                 desc: "設定ポートが他のアプリに使用されていないか確認してください。lsof -i :\(AppState.shared.proxyPort) で確認できます。")
                        HelpItem(title: "API 認証エラー",
                                 desc: "該当するキーが Keychain に登録されているか確認してください。キーの横に ✅ が表示されていれば登録済みです。")
                        HelpItem(title: "モードを切り替えたい",
                                 desc: "メニューバー → Change Mode、またはツールバー → Help → Change Mode から切り替えできます。")
                        HelpItem(title: "オンボーディングを再表示",
                                 desc: "メニューバー → Help → Show Tutorial から再度チュートリアルを表示できます。")
                    }
                }

                // Keyboard Shortcuts
                HelpSection(title: "キーボードショートカット", icon: "keyboard") {
                    VStack(alignment: .leading, spacing: 6) {
                        ShortcutRow(keys: "⌘ K", action: "メイン画面を開く")
                        ShortcutRow(keys: "⌘ N", action: "新しいキーを追加")
                        ShortcutRow(keys: "⌘ Q", action: "アプリを終了")
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
                    Label("Show Tutorial Again", systemImage: "play.circle")
                }
                .buttonStyle(.bordered)
            }
            .padding(24)
        }
        .frame(width: 580, height: 640)
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
