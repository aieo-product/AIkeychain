import Foundation

/// シークレット値をUI表示用にマスクする。
///
/// 短い値は長さも含めて完全に隠す（固定長のアスタリスクを返す）。
/// 十分に長い値は先頭の短いプレフィックスのみを見せ、末尾は絶対に出さない
/// （末尾を見せると総当たりの手掛かりになり得るため）。
enum SecretMask {
    /// 値が `revealThreshold` 未満の場合に返す、固定長の完全マスク。
    /// 固定長にすることで元の値の長さも推測できないようにする。
    private static let fullMask = String(repeating: "*", count: 8)

    /// これ未満の長さの値は完全にマスクする。
    private static let revealThreshold = 16

    /// 長い値で見せてよいプレフィックスの文字数。
    private static let prefixLength = 4

    static func mask(_ value: String) -> String {
        guard value.count >= revealThreshold else {
            return fullMask
        }
        return String(value.prefix(prefixLength)) + "…"
    }
}

/// シェル export で安全に使える環境変数名かどうかを検証する。
///
/// `.env` インポートやキーエディタから、シェルインジェクションや
/// 意図しないコマンド実行につながり得るキー名（空白・記号・シェル制御文字を
/// 含むものなど）が Keychain に書き込まれるのを防ぐ。
enum EnvVarName {
    private static let pattern = #"^[A-Za-z_][A-Za-z0-9_]*$"#

    /// 渡された文字列を **そのまま**（トリムせず）検証する。
    ///
    /// トリムして検証すると「`isValid(x)` が true でも、実際に保存/補間するのは
    /// 別の文字列（トリム後）」という不整合が生じ、"`isValid(x)` ⇒ x は安全" の
    /// 不変条件が崩れる。したがってここでは正規化しない。呼び出し側は
    /// **保存する文字列そのもの**（必要ならトリム済み）を渡すこと。
    /// パターンは複数行アンカーを使わない（`^`/`$` は文字列全体の端）ため、
    /// 改行を含む名前（例 "A\nB"）は確実に false になる。
    static func isValid(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        return name.range(of: pattern, options: .regularExpression) != nil
    }
}
