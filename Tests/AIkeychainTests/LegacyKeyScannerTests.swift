import Testing
@testable import AIkeychain

/// v1 取り残しキー検出（アップグレードツアー用 / #188）の分類ロジック。
/// CLI の findUnmigratedKeys（cli/test/unit.test.js）と同一規則であることを保証する。
@Suite("LegacyKeyScanner Tests")
struct LegacyKeyScannerTests {

    private func scan(_ records: [(service: String?, account: String?)]) -> [String] {
        LegacyKeyScanner.unmigratedKeyNames(from: records)
    }

    @Test("Reports legacy-only keys and skips those already in managed")
    func reportsLegacyOnly() {
        let names = scan([
            // managed 済み → 対象外（旧 GUI にコピーが残っていても）
            (service: "com.aieo.aikeychain.managed", account: "MIGRATED_KEY"),
            (service: "com.aieo.aikeychain", account: "MIGRATED_KEY"),
            // 旧 GUI store のみ → 対象
            (service: "com.aieo.aikeychain", account: "GUI_ONLY_KEY"),
            // manual スキームのみ → 対象（service 名がキー名）
            (service: "MANUAL_ONLY_KEY", account: "takehiro"),
            // env 変数形でない service は対象外（他アプリ）
            (service: "com.vendor.other", account: "x"),
            (service: "lowercase_svc", account: "x"),
        ])
        #expect(names == ["GUI_ONLY_KEY", "MANUAL_ONLY_KEY"])
    }

    @Test("Returns empty when everything is already managed")
    func emptyWhenAllManaged() {
        #expect(scan([
            (service: "com.aieo.aikeychain.managed", account: "A_KEY"),
            (service: "com.aieo.aikeychain.managed", account: "B_KEY"),
        ]).isEmpty)
    }

    @Test("Never reports the app-reserved share/sign keys")
    func excludesReservedServices() {
        #expect(scan([
            (service: "com.aieo.aikeychain.sharekey", account: "private_key"),
            (service: "com.aieo.aikeychain.signkey", account: "signing_key"),
        ]).isEmpty)
    }

    @Test("Ignores manual-shape false positives (lowercase / dotted / leading digit)")
    func ignoresNonEnvVarNames() {
        #expect(scan([
            (service: "iCloud", account: "x"),
            (service: "com.apple.something", account: "x"),
            (service: "9INVALID", account: "x"),
            (service: "lower_token", account: "x"),
        ]).isEmpty)
    }

    @Test("shouldShow is false with no legacy keys")
    func shouldShowFalseWhenEmpty() {
        // 旧キーが無ければ UserDefaults を読むまでもなく false（新規インストール）
        #expect(UpgradeTourView.shouldShow(legacyKeyNames: []) == false)
    }
}
