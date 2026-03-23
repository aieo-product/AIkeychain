import Foundation
import Observation

@Observable
final class OnboardingViewModel {
    var currentStep: OnboardingStep = .welcome
    var isComplete = false

    private static let completedKey = "onboarding_completed"

    static var hasCompleted: Bool {
        UserDefaults.standard.bool(forKey: completedKey)
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
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        isComplete = true
    }

    /// デバッグ/テスト用: オンボーディングをリセット
    static func reset() {
        UserDefaults.standard.removeObject(forKey: completedKey)
    }
}
