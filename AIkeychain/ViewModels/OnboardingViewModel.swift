import Foundation
import Observation

@Observable
final class OnboardingViewModel {
    var currentStep: OnboardingStep = .welcome
    var isComplete = false

    private static let completedKey = "onboarding_completed"

    /// 完了フラグの保存先。本番は `.standard`、テストは分離スイートを注入する。
    @ObservationIgnored private let defaults: UserDefaults

    /// 「閉じる」ボタン / Esc で閉じられるか（#203）。
    /// 表示開始時点で完了済み（= ヘルプからの再表示）なら true、初回は false（必須フロー）。
    /// init でスナップショットし、フロー途中で complete() しても変化しない。
    let canDismiss: Bool

    static var hasCompleted: Bool {
        UserDefaults.standard.bool(forKey: completedKey)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.canDismiss = defaults.bool(forKey: Self.completedKey)
    }

    var progress: Double {
        Double(currentStep.rawValue) / Double(OnboardingStep.allCases.count - 1)
    }

    var canGoBack: Bool {
        currentStep.rawValue > 0
    }

    var isLastStep: Bool {
        currentStep == .completion
    }

    func next() {
        let nextRaw = currentStep.rawValue + 1
        if let next = OnboardingStep(rawValue: nextRaw) {
            currentStep = next
        }
    }

    func back() {
        let prevRaw = currentStep.rawValue - 1
        if let prev = OnboardingStep(rawValue: prevRaw) {
            currentStep = prev
        }
    }

    func complete() {
        defaults.set(true, forKey: Self.completedKey)
        isComplete = true
    }

    /// デバッグ/テスト用: オンボーディングをリセット
    static func reset() {
        UserDefaults.standard.removeObject(forKey: completedKey)
    }
}
