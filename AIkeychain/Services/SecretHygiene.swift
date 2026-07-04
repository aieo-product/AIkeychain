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

    static func isValid(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }
}
