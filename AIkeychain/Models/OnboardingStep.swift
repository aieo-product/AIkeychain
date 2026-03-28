import Foundation

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome = 0
    case modeSelect
    case registerKeys
    case setupShell
    case completion

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: "Welcome"
        case .modeSelect: "Choose Mode"
        case .registerKeys: "Register Keys"
        case .setupShell: "Shell Setup"
        case .completion: "Complete!"
        }
    }

    var systemImage: String {
        switch self {
        case .welcome: "key.fill"
        case .modeSelect: "switch.2"
        case .registerKeys: "plus.circle"
        case .setupShell: "terminal"
        case .completion: "checkmark.seal.fill"
        }
    }

    var canSkip: Bool {
        switch self {
        case .welcome, .modeSelect, .completion: false
        case .registerKeys, .setupShell: true
        }
    }
}
