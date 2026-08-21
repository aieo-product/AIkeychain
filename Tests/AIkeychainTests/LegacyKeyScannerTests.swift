import Testing
@testable import AIkeychain

/// v1 取り残しキー検出（アップグレードツアー用 / #188）の分類ロジック。
/// 対象は旧 GUI store（service=com.aieo.aikeychain）のみ = AI KeyChain が確実に
/// 所有していた service。managed に無いものを返す。
@Suite("LegacyKeyScanner Tests")
struct LegacyKeyScannerTests {

    private func scan(_ records: [(service: String?, account: String?)]) -> [String] {
        LegacyKeyScanner.unmigratedKeyNames(from: records)
    }

    @Test("Reports legacy GUI-store keys not yet in managed, sorted")
    func reportsLegacyGuiOnly() {
        let names = scan([
            // managed 済み → 対象外（旧 GUI にコピーが残っていても）
            (service: "com.aieo.aikeychain.managed", account: "MIGRATED_KEY"),
            (service: "com.aieo.aikeychain", account: "MIGRATED_KEY"),
            // 旧 GUI store のみ → 対象（ソート確認のため複数）
            (service: "com.aieo.aikeychain", account: "ZEBRA_KEY"),
            (service: "com.aieo.aikeychain", account: "ALPHA_KEY"),
        ])
        #expect(names == ["ALPHA_KEY", "ZEBRA_KEY"])
    }

    @Test("Does NOT report manual-scheme / other-app services (avoids false positives)")
    func ignoresManualAndOtherApps() {
        // v1 の manual スキームや他アプリの UPPER_SNAKE service は所有が曖昧なので
        // 対象にしない（新規インストールでの誤発火を防ぐ / #189 レビュー D-Q）。
        #expect(scan([
            (service: "MANUAL_TOKEN", account: "takehiro"),   // manual スキーム
            (service: "VPN_TOKEN", account: "user"),          // 他アプリ
            (service: "com.apple.something", account: "x"),
            (service: "iCloud", account: "x"),
        ]).isEmpty)
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

    @Test("Skips records with nil/empty account and nil service (no blank tour rows)")
    func skipsUnusableRecords() {
        #expect(scan([
            (service: "com.aieo.aikeychain", account: nil),
            (service: "com.aieo.aikeychain", account: ""),
            (service: nil, account: "ORPHAN"),
        ]).isEmpty)
    }

    @Test("shouldShow is false with no legacy keys")
    func shouldShowFalseWhenEmpty() {
        // 旧キーが無ければ UserDefaults を読むまでもなく false（新規インストール）
        #expect(UpgradeTourView.shouldShow(legacyKeyNames: []) == false)
    }
}
