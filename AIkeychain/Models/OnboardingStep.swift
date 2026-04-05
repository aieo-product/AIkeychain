import Foundation

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case language = 0
    case welcome
    case modeSelect
    case registerKeys
    case setupShell
    case completion

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .language: L10n.t("step_language")
        case .welcome: L10n.t("step_welcome")
        case .modeSelect: L10n.t("step_mode")
        case .registerKeys: L10n.t("step_keys")
        case .setupShell: L10n.t("step_shell")
        case .completion: L10n.t("step_complete")
        }
    }

    var systemImage: String {
        switch self {
        case .language: "globe"
        case .welcome: "key.fill"
        case .modeSelect: "switch.2"
        case .registerKeys: "plus.circle"
        case .setupShell: "terminal"
        case .completion: "checkmark.seal.fill"
        }
    }

    var canSkip: Bool {
        switch self {
        case .language, .welcome, .modeSelect, .completion: false
        case .registerKeys, .setupShell: true
        }
    }
}
