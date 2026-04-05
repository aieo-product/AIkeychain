import Foundation

/// アプリ内表示言語
enum AppLanguage: String, CaseIterable, Identifiable {
    case ja
    case en

    var id: String { rawValue }

    /// 表示用ラベル（言語自身の名称で固定表示）
    var displayName: String {
        switch self {
        case .ja: "日本語"
        case .en: "English"
        }
    }

    var flag: String {
        switch self {
        case .ja: "🇯🇵"
        case .en: "🇺🇸"
        }
    }
}
