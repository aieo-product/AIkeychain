import SwiftUI

/// .zshrc に残っている API キーの直接参照を調査・削除するためのコマンドガイド
/// アプリ自体はコマンド実行しない — ユーザーがターミナルでコピペして使う
struct CleanupView: View {
    @Environment(\.dismiss) private var dismiss

    private let port = AppState.shared.proxyPort

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 28))
                        .foregroundStyle(AppColors.accentGradient)
                    VStack(alignment: .leading) {
                        Text("Shell Cleanup")
                            .font(AppFonts.sectionTitle)
                        Text(L10n.s(ja: "API キーの直接参照を安全に除去", en: "Safely remove direct API key references"))
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

                // Why
                VStack(alignment: .leading, spacing: 6) {
                    Label(L10n.s(ja: "なぜクリーンアップが必要？", en: "Why is cleanup needed?"), systemImage: "exclamationmark.triangle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.orange)

                    Text(L10n.s(
                        ja: """
                        .zshrc に `export API_KEY=$(security find-generic-password ...)` の形式で API キーを取得していると:

                        1. **env コマンドでキーが丸見え** — AI ツールが意図せずキーを読み取るリスク
                        2. **SSH 経由で Keychain 承認ダイアログが出せない** — Tailscale SSH 等でエラーになる
                        3. **シェル起動が遅くなる** — Keychain アクセスに時間がかかる

                        AI KeyChain プロキシ経由なら、これらの問題を全て解決できます。
                        """,
                        en: """
                        If your .zshrc fetches API keys with `export API_KEY=$(security find-generic-password ...)`:

                        1. **Keys are visible via env command** — risk of AI tools reading keys unintentionally
                        2. **Cannot show Keychain auth dialog via SSH** — causes errors with Tailscale SSH, etc.
                        3. **Slower shell startup** — Keychain access takes time

                        Using AI KeyChain proxy solves all of these issues.
                        """))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))

                Divider()

                // Step 1: 調査
                CommandSection(
                    step: "1",
                    title: L10n.s(ja: "現在の .zshrc を調査", en: "Inspect current .zshrc"),
                    description: L10n.s(ja: ".zshrc に残っている API キーの直接参照を確認します。", en: "Check for direct API key references remaining in .zshrc."),
                    command: "grep -n 'security find-generic-password' ~/.zshrc",
                    note: L10n.s(ja: "結果が表示された行が、API キーを環境変数に直接読み込んでいる箇所です。", en: "Lines shown in the result are where API keys are loaded directly into environment variables.")
                )

                // Step 2: AI系キーの削除
                CommandSection(
                    step: "2",
                    title: L10n.s(ja: "AI 系 API キーの直接参照を削除", en: "Remove direct AI API key references"),
                    description: L10n.s(ja: "プロキシ対応の AI API キーは BASE_URL 経由に切り替えます。\n以下のコマンドで該当行を削除してください。", en: "Switch proxy-compatible AI API keys to use BASE_URL.\nDelete the matching lines with the commands below."),
                    command: """
                    # 削除対象の行を確認（ドライラン）
                    grep -n 'ANTHROPIC_API_KEY\\|OPENAI_API_KEY\\|XAI_API_KEY' ~/.zshrc | grep 'security'

                    # 確認後、該当行を削除
                    sed -i '' '/security.*ANTHROPIC_API_KEY/d' ~/.zshrc
                    sed -i '' '/security.*OPENAI_API_KEY/d' ~/.zshrc
                    sed -i '' '/security.*XAI_API_KEY/d' ~/.zshrc
                    """,
                    note: L10n.s(ja: "削除後、代わりに BASE_URL を追加してください（Step 3）。", en: "After deletion, add the BASE_URL instead (Step 3).")
                )

                // Step 3: BASE_URL追加
                CommandSection(
                    step: "3",
                    title: L10n.s(ja: "プロキシ BASE_URL を設定", en: "Configure proxy BASE_URL"),
                    description: L10n.s(ja: "以下を .zshrc に追加します。アプリの「Enable Secure Proxy」ボタンでも自動設定できます。", en: "Add the following to .zshrc. You can also auto-configure via the \"Enable Secure Proxy\" button in the app."),
                    command: """
                    cat >> ~/.zshrc << 'EOF'

                    # --- AI KeyChain Proxy Configuration ---
                    export ANTHROPIC_BASE_URL=http://localhost:\(port)
                    export OPENAI_BASE_URL=http://localhost:\(port)
                    export XAI_BASE_URL=http://localhost:\(port)
                    # --- End AI KeyChain ---
                    EOF
                    """,
                    note: L10n.s(ja: "既に設定済みの場合は重複追加しないでください。", en: "Do not add duplicates if already configured.")
                )

                // Step 4: 非AI系の確認
                CommandSection(
                    step: "4",
                    title: L10n.s(ja: "非 AI 系トークンの確認（任意）", en: "Check non-AI tokens (optional)"),
                    description: L10n.s(ja: "Cloudflare / GitHub / GitLab 等のトークンもクリーンアップしたい場合。\nこれらはプロキシ非対応のため、用途に応じて判断してください。", en: "For cleaning up Cloudflare / GitHub / GitLab tokens as well.\nThese are not proxy-compatible, so decide based on your use case."),
                    command: """
                    # 残っている security 参照を一覧
                    grep -n 'security find-generic-password' ~/.zshrc

                    # SSH 経由でも使いたい場合は ACL を事前許可
                    # （ログインパスワードの入力が必要）
                    security set-generic-password-partition-list \\
                      -s "GITHUB_TOKEN" -a "$USER" \\
                      -S "apple-tool:,apple:" -k "ログインパスワード"
                    """,
                    note: L10n.s(ja: "ACL 設定はローカルの GUI セッションで実行してください。", en: "Run ACL configuration in a local GUI session.")
                )

                // Step 5: 反映
                CommandSection(
                    step: "5",
                    title: L10n.s(ja: "設定を反映", en: "Apply changes"),
                    description: L10n.s(ja: "変更を現在のシェルに反映します。", en: "Apply the changes to the current shell."),
                    command: "source ~/.zshrc",
                    note: L10n.s(ja: "新しいターミナルを開いても反映されます。", en: "Changes will also take effect in new terminal windows.")
                )

                // Step 6: 確認
                CommandSection(
                    step: "6",
                    title: L10n.s(ja: "確認", en: "Verify"),
                    description: L10n.s(ja: "env に API キーが露出していないことを確認します。", en: "Verify that API keys are not exposed in env."),
                    command: """
                    # AI API キーが env に出ていないことを確認
                    env | grep -i 'ANTHROPIC_API_KEY\\|OPENAI_API_KEY\\|XAI_API_KEY'

                    # BASE_URL が設定されていることを確認
                    env | grep -i 'BASE_URL'
                    """,
                    note: L10n.s(ja: "API_KEY の grep 結果が空なら成功です。BASE_URL が表示されれば OK。", en: "Success if the API_KEY grep returns empty. OK if BASE_URL is shown.")
                )
            }
            .padding(24)
        }
        .frame(width: 620, height: 680)
    }
}

// MARK: - Components

private struct CommandSection: View {
    let step: String
    let title: String
    let description: String
    let command: String
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text(step)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(AppColors.aiPurple, in: Circle())

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))

                    Text(description)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    // Command block
                    HStack(alignment: .top) {
                        Text(command.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .foregroundStyle(.primary)

                        Spacer()

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(
                                command.trimmingCharacters(in: .whitespacesAndNewlines),
                                forType: .string
                            )
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Copy to clipboard")
                    }
                    .padding(10)
                    .background(Color(.textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

                    Label(note, systemImage: "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}
