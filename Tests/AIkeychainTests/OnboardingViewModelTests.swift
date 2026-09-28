import Testing
import Foundation
@testable import AIkeychain

/// #203: ヘルプから再表示したオンボーディングを閉じられるか（canDismiss）の判定。
/// 実アプリの defaults ドメインを汚さないよう、テストごとに分離した UserDefaults スイートを使う。
@Suite("OnboardingViewModel Tests")
struct OnboardingViewModelTests {

    private func isolatedDefaults() -> (UserDefaults, String) {
        let suite = "test-onboarding-\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    @Test("完了済み（再表示）なら閉じられる")
    func canDismissWhenCompleted() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "onboarding_completed")

        let vm = OnboardingViewModel(defaults: defaults)
        #expect(vm.canDismiss == true)
    }

    @Test("未完了（初回）なら閉じられない")
    func cannotDismissOnFirstRun() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let vm = OnboardingViewModel(defaults: defaults)
        #expect(vm.canDismiss == false)
    }

    @Test("初回フロー途中で complete() しても canDismiss は変わらない（スナップショット）")
    func canDismissIsSnapshotAtInit() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let vm = OnboardingViewModel(defaults: defaults)
        vm.complete()
        #expect(vm.canDismiss == false)
        // 完了フラグは注入した defaults に書かれる（.standard は触らない）
        #expect(defaults.bool(forKey: "onboarding_completed") == true)
        #expect(vm.isComplete == true)
    }

    @Test("完了済みで開始した場合も complete() 後に canDismiss は true のまま")
    func completedStaysDismissable() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "onboarding_completed")

        let vm = OnboardingViewModel(defaults: defaults)
        vm.complete()
        #expect(vm.canDismiss == true)
    }
}
