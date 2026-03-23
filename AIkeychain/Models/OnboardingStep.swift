import Foundation

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome = 0
    case proxyExplain
    case registerKeys
    case setupShell
    case completion

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: "Welcome to AI KeyChain"
        case .proxyExplain: "How It Works"
        case .registerKeys: "Register Your Keys"
        case .setupShell: "Connect Your Shell"
        case .completion: "You're All Set!"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome: "AI API キーをセキュアに管理するmacOSアプリ"
        case .proxyExplain: "環境変数にキーを露出させない仕組み"
        case .registerKeys: "Keychain に API キーを登録"
        case .setupShell: ".zshrc にプロキシ設定を追加"
        case .completion: "セキュアな AI 開発環境の完成"
        }
    }

    var systemImage: String {
        switch self {
        case .welcome: "key.fill"
        case .proxyExplain: "shield.checkered"
        case .registerKeys: "plus.circle"
        case .setupShell: "terminal"
        case .completion: "checkmark.seal.fill"
        }
    }

    var canSkip: Bool {
        switch self {
        case .welcome, .completion: false
        case .proxyExplain, .registerKeys, .setupShell: true
        }
    }
}
