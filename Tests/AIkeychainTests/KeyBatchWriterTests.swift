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
