import Foundation
import Testing
@testable import AIkeychain

/// `.env` インポート / キー共有受信の書込み経路（#215）。
/// `BlindExistsKeychainService` は exists() が常に false（照会失敗の fail-open を再現）で、
/// create() だけが既存を duplicateItem で拒否する。
@Suite("KeyBatchWriter (#215)")
struct KeyBatchWriterTests {

    private func uniqueName(_ prefix: String) -> String {
        prefix + "_" + UUID().uuidString.replacingOccurrences(of: "-", with: "_")
    }

    // MARK: .env インポート経路（EnvImportView.performImport）

    @Test("Import: an existing key not marked overwrite is skipped, not overwritten (#215)")
    func importSkipsExistingWhenNotOverwrite() {
        let blind = BlindExistsKeychainService()
        let existing = uniqueName("IMP_EXISTING")
        blind.store[existing] = "original"

        let result = KeyBatchWriter.write([.init(account: existing, value: "from_env")],
                                          overwriting: [], keychain: blind)

        #expect(blind.store[existing] == "original")
        #expect(result.skippedExisting == [existing])
        #expect(result.saved.isEmpty)
        #expect(result.failed.isEmpty)
        #expect(result.unsupported.isEmpty)
    }

    @Test("Import: explicit overwrite still overwrites; new key is created (#215)")
    func importOverwriteAndNew() {
        let blind = BlindExistsKeychainService()
        let overwritten = uniqueName("IMP_OW")
        let fresh = uniqueName("IMP_NEW")
        blind.store[overwritten] = "original"

        let result = KeyBatchWriter.write(
            [.init(account: overwritten, value: "from_env"), .init(account: fresh, value: "new_value")],
            overwriting: [overwritten], keychain: blind)

        #expect(blind.store[overwritten] == "from_env")
        #expect(blind.store[fresh] == "new_value")
        #expect(result.saved == [overwritten, fresh])
        #expect(result.skippedExisting.isEmpty)
    }

    // MARK: .env 内の同名キー（PR #218 レビュー Astra / Fable）

    @Test("EnvParser: duplicate keys fold to one entry, last wins, first position kept (#215)")
    func parserDuplicateKeysLastWins() {
        let entries = EnvParser.parse("export K=first\nOTHER=x\nK=second\n")
        #expect(entries.map(\.key) == ["K", "OTHER"])
        #expect(entries.first { $0.key == "K" }?.value == "second")
    }

    @Test("EnvParser: last assignment excluded (empty value) drops the key entirely (#215)")
    func parserLastAssignmentEmptyDropsKey() {
        #expect(EnvParser.parse("export OPENAI_API_KEY=old\nexport OPENAI_API_KEY=\n").isEmpty)
    }

    @Test("EnvParser: last assignment excluded (shell expansion) drops the key entirely (#215)")
    func parserLastAssignmentExpansionDropsKey() {
        #expect(EnvParser.parse("K=old\nK=$(security find-generic-password -s x -w)\n").isEmpty)
        #expect(EnvParser.parse("K=old\nK=$OTHER_VAR\n").isEmpty)
        // 閉じない複数行クォート（破棄される代入）が最後でも同様
        #expect(EnvParser.parse("K=old\nK=\"never closed\n").map(\.key) == [])
    }

    @Test("EnvParser: an excluded assignment followed by a valid one keeps the valid value (#215)")
    func parserExcludedThenValid() {
        let simple = EnvParser.parse("K=old\nK=new\n")
        #expect(simple.map(\.key) == ["K"])
        #expect(simple.first?.value == "new")

        let expThenReal = EnvParser.parse("K=$(cmd)\nK=real\n")
        #expect(expThenReal.map(\.key) == ["K"])
        #expect(expThenReal.first?.value == "real")

        // 除外された代入は位置を持たない: 最初に受理された位置に並ぶ
        let ordered = EnvParser.parse("K=$(cmd)\nOTHER=x\nK=real\n")
        #expect(ordered.map(\.key) == ["OTHER", "K"])
        #expect(ordered.last?.value == "real")

        // 複数行クォートの論理行も 1 代入として後勝ちに参加する（#201）
        let multi = EnvParser.parse("K=old\nK=\"line1\nline2\"\n")
        #expect(multi.map(\.key) == ["K"])
        #expect(multi.first?.value == "line1\nline2")
    }

    @Test("EnvParser: boundary cases of the last-assignment rule (#215, Fable audit)")
    func parserLastAssignmentBoundaries() {
        // 3) システム変数も後勝ち判定に入るが結果は空。非代入行（コメント・値なし export・無効キー）は判定に影響しない
        #expect(EnvParser.parse("PATH=a\nPATH=\n").isEmpty)
        let nonAssign = EnvParser.parse("K=v\n# K=\nexport K\n1K=\n")
        #expect(nonAssign.map(\.key) == ["K"])
        #expect(nonAssign.first?.value == "v")
        // 4) 閉じクォート後の不正な trailer で破棄された最後の代入
        #expect(EnvParser.parse("K=new\nK=\"a\nb\" junk\n").isEmpty)
        // 5) `K = ` のキー前後空白も同じキーへの代入
        #expect(EnvParser.parse("export K=old\nK = \n").isEmpty)
        // 6) 未終端クォートの本文行から記録された偽キーは他のキーを汚さない。
        // 本文行 `MIIEvQ==` 自体の除外は #208（PR #211）の `=` パディング判定の担当なので、
        // ここでは #208 の有無に依存しない不変条件（PK は落ち、NEXT は値ごと残る）を固定する。
        // #211 マージ後は keys == ["NEXT"] になる。
        let pem = EnvParser.parse("PK=\"-----BEGIN\nMIIEvQ==\nNEXT=ok\n")
        #expect(!pem.contains { $0.key == "PK" })
        #expect(pem.filter { $0.key == "NEXT" }.map(\.value) == ["ok"])
    }

    @Test("Import: a parsed .env never puts one account in both saved and skippedExisting (#215)")
    func importDuplicateKeyNotBothSavedAndSkipped() {
        let blind = BlindExistsKeychainService()
        let name = uniqueName("IMP_DUP")
        let parsed = EnvParser.parse("export \(name)=first\nOTHER_\(name)=x\n\(name)=second\n")
        let result = KeyBatchWriter.write(parsed.map { .init(account: $0.account, value: $0.value) },
                                          overwriting: [], keychain: blind)

        #expect(blind.store[name] == "second")
        #expect(result.saved.contains(name))
        #expect(Set(result.saved).isDisjoint(with: result.skippedExisting))
        #expect(result.skippedExisting.isEmpty)
    }

    // MARK: キー共有受信経路（ShareKeysView.ReceiveTab.importDecrypted）

    @Test("Share: mixed batch — only confirmed overwrite names are replaced (#215)")
    func shareMixedBatch() {
        let blind = BlindExistsKeychainService()
        let confirmed = uniqueName("SHR_OW")     // 上書きバッジ＋承諾済み
        let hidden = uniqueName("SHR_HIDDEN")    // 既存だが exists() が false を返し「新規」扱い
        let fresh = uniqueName("SHR_NEW")
        blind.store[confirmed] = "orig_confirmed"
        blind.store[hidden] = "orig_hidden"

        let result = KeyBatchWriter.write(
            [.init(account: confirmed, value: "shared_1"),
             .init(account: hidden, value: "shared_2"),
             .init(account: fresh, value: "shared_3")],
            overwriting: [confirmed], keychain: blind)

        #expect(blind.store[confirmed] == "shared_1")
        #expect(blind.store[hidden] == "orig_hidden")
        #expect(blind.store[fresh] == "shared_3")
        #expect(result.saved == [confirmed, fresh])
        #expect(result.skippedExisting == [hidden])
        #expect(result.failed.isEmpty)
    }

    @Test("Share: app-managed values are filtered out before writing (#219)")
    func shareFiltersAppManaged() {
        let entries: [KeyBatchWriter.Entry] = [
            .init(account: "OPENAI_API_KEY", value: "keychain://OPENAI_API_KEY"),
            .init(account: "GITHUB_TOKEN", value: "<VALUE>"),
            .init(account: "AIKEYCHAIN_SESSION_TOKEN", value: "abc"),
            .init(account: "ANTHROPIC_API_KEY", value: "sk-ant-real"),
            .init(account: "NOTE", value: "my keychain://notes"),
        ]
        let (writable, appManaged) = KeyBatchWriter.partitionAppManaged(entries)
        #expect(writable.map(\.account) == ["ANTHROPIC_API_KEY", "NOTE"])
        #expect(appManaged == ["OPENAI_API_KEY", "GITHUB_TOKEN", "AIKEYCHAIN_SESSION_TOKEN"])
    }

    @Test("Unsupported value and other errors keep their own tallies (#215 regression)")
    func errorTalliesUnchanged() {
        let keychain = ThrowingWriteKeychainService()
        keychain.errors = ["BAD_VALUE": KeychainError.invalidData, "LOCKED": KeychainError.interactionRequired]

        let result = KeyBatchWriter.write(
            [.init(account: "BAD_VALUE", value: "x"), .init(account: "LOCKED", value: "y")],
            overwriting: ["LOCKED"], keychain: keychain)

        #expect(result.unsupported == ["BAD_VALUE"])
        #expect(result.failed == ["LOCKED"])
        #expect(result.saved.isEmpty)
        #expect(result.skippedExisting.isEmpty)
    }
}

/// save/create がアカウントごとに指定エラーを投げるテストダブル（#215）。
final class ThrowingWriteKeychainService: KeychainServiceProtocol {
    var errors: [String: Error] = [:]
    var store: [String: String] = [:]
    func save(value: String, for account: String) throws {
        if let e = errors[account] { throw e }
        store[account] = value
    }
    func create(value: String, for account: String) throws {
        if let e = errors[account] { throw e }
        guard store[account] == nil else { throw KeychainError.duplicateItem }
        store[account] = value
    }
    func retrieve(for account: String) throws -> String? { store[account] }
    func retrieveNoninteractive(for account: String) throws -> String? { store[account] }
    func delete(for account: String) throws { store.removeValue(forKey: account) }
    func exists(for account: String) -> Bool { false }
    func allAccounts() -> [String] { Array(store.keys) }
}
