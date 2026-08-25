import SwiftUI

/// v1.x → v2.0 アップグレード時に、取り残しキーの再登録と新しい使い方を案内する
/// ツアー (#188)。旧キーが検出され、まだ表示していない場合にのみ出す。
struct UpgradeTourView: View {
    /// 検出された旧 v1 キー名（managed に無いもの）。
    let legacyKeyNames: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    private static let seenKey = "v2_upgrade_tour_seen"

    /// 旧キーが在り、かつ未表示のとき true。表示条件の単一の入口。
    static func shouldShow(legacyKeyNames: [String]) -> Bool {
        !legacyKeyNames.isEmpty && !UserDefaults.standard.bool(forKey: seenKey)
    }

    static func markSeen() {
        UserDefaults.standard.set(true, forKey: seenKey)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    switch page {
                    case 0: whatChanged
                    case 1: reregister
                    default: howItWorks
                    }
                }
                .padding(28)
            }

            Divider()
            footer
        }
        .frame(width: 560, height: 560)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 30))
                .foregroundStyle(AppColors.aiPurple)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.s(ja: "AI KeyChain 2.0 へようこそ", en: "Welcome to AI KeyChain 2.0"))
                    .font(.system(size: 20, weight: .bold))
                Text(L10n.s(ja: "保存方式が新しくなりました", en: "The way keys are stored has changed"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Page 0: 何が変わったか
    private var whatChanged: some View {
        VStack(alignment: .leading, spacing: 14) {
            tourRow(icon: "arrow.triangle.2.circlepath", color: AppColors.aiPurple,
                    title: L10n.s(ja: "単一の保管場所に統一", en: "One unified store"),
                    body: L10n.s(
                        ja: "2.0 では全てのキーを新しい managed namespace に保存します。AI エージェント（Claude Code / Codex 等）が `akc run` でヘッドレスに読める、確認ダイアログの出ない方式です。",
                        en: "2.0 stores every key in a new managed namespace — one that AI agents (Claude Code, Codex, …) can read headlessly via `akc run`, with no consent dialogs."))
            tourRow(icon: "exclamationmark.triangle.fill", color: .orange,
                    title: L10n.s(ja: "以前のキーは再登録が必要", en: "Your earlier keys need re-registering"),
                    body: L10n.s(
                        ja: "1.x で登録したキーは自動では読み込まれなくなりました（削除はされていません）。次のページで対象のキーを確認できます。",
                        en: "Keys you registered in 1.x are no longer read automatically (they are not deleted). The next page lists which ones."))
        }
    }

    // MARK: - Page 1: 再登録
    private var reregister: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.s(ja: "再登録が必要なキー（\(legacyKeyNames.count) 件）",
                        en: "Keys to re-register (\(legacyKeyNames.count))"))
                .font(.system(size: 15, weight: .semibold))
            Text(L10n.s(ja: "以前の保存場所に見つかったキーです。同じ名前で登録し直すと 2.0 で使えるようになります。",
                        en: "These were found in the old location. Re-register each with the same name to use it in 2.0."))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(legacyKeyNames, id: \.self) { name in
                    HStack(spacing: 8) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(name).font(.system(size: 12, design: .monospaced))
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.s(ja: "登録方法", en: "How to re-register"))
                    .font(.system(size: 13, weight: .medium))
                Label(L10n.s(ja: "一括で引き継ぐ: ターミナルで  akc migrate（akc 未導入なら npx -y aikeychain migrate）", en: "Migrate them all at once — in a terminal:  akc migrate  (no CLI yet? npx -y aikeychain migrate)"), systemImage: "square.stack.3d.up")
                    .font(.system(size: 12, weight: .medium))
                Label(L10n.s(ja: "このアプリの「+」から 1 件ずつ追加する", en: "Or add one by one from the “+” in this app"), systemImage: "plus.circle")
                    .font(.system(size: 12))
                Label(L10n.s(ja: "またはターミナルで  akc set <KEY>", en: "Or in a terminal:  akc set <KEY>"), systemImage: "terminal")
                    .font(.system(size: 12))
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Page 2: 新しい使い方
    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 14) {
            tourRow(icon: "link", color: AppColors.cloudBlue,
                    title: L10n.s(ja: "keychain:// 参照 + akc run", en: "keychain:// references + akc run"),
                    body: L10n.s(
                        ja: "`export OPENAI_API_KEY=keychain://OPENAI_API_KEY` として `akc run -- <command>` で起動すると、実際の値は子プロセスにだけ注入され、親シェルには出ません。",
                        en: "Set `export OPENAI_API_KEY=keychain://OPENAI_API_KEY`, then launch via `akc run -- <command>`. The real value is injected into the child process only."))
            tourRow(icon: "checkmark.seal.fill", color: AppColors.configured,
                    title: L10n.s(ja: "エージェント設定は akc init", en: "Set up agents with akc init"),
                    body: L10n.s(
                        ja: "`akc init` を一度実行すると、Claude Code / Codex がこのマシンで AI KeyChain を自動的に使えるようになります。",
                        en: "Run `akc init` once so Claude Code / Codex discover and use AI KeyChain on this machine."))
        }
    }

    private func tourRow(icon: String, color: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(body).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Footer nav
    private var footer: some View {
        HStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(i == page ? AppColors.aiPurple : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
            }
            Spacer()
            if page > 0 {
                Button(L10n.s(ja: "戻る", en: "Back")) { withAnimation { page -= 1 } }
            }
            if page < 2 {
                Button(L10n.s(ja: "次へ", en: "Next")) { withAnimation { page += 1 } }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            } else {
                Button(L10n.s(ja: "はじめる", en: "Get started")) {
                    Self.markSeen()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
    }
}
