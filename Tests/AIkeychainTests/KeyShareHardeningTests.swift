import Foundation
import CryptoKit
import Security
import Testing
@testable import AIkeychain

/// #127 署名鍵ハードニング（SE 抽象 / ensureSigningKey レース）と
/// #126 TOFU ピン留め / 鮮度のテスト。
/// すべて in-memory（login-Keychain 非依存）。SE 生成は CI で検証不能なため
/// SecureEnclave.isAvailable でガードし、ソフトウェア経路を決定的にテストする。
@Suite("KeyShare Hardening (#126 / #127)")
struct KeyShareHardeningTests {

    private let sampleKeys: [(envVarName: String, value: String)] = [
        ("OPENAI_API_KEY", "sk-test-value-1234567890abcdef"),
        ("GITHUB_TOKEN", "ghp_abcdefghijklmnopqrstuvwxyz0123456789"),
    ]

    // MARK: - #127 ensureSigningKey race (resolveSigningIdentity, pure)

    @Test("resolveSigningIdentity: existing key short-circuits, never creates")
    func resolveExistingShortCircuits() throws {
        let existing = P256.Signing.PrivateKey()
        var created = false
        let result = try KeyShareService.resolveSigningIdentity(
            load: { .software(existing) },
            create: { created = true; return (.software(P256.Signing.PrivateKey()), Data()) },
            add: { _ in errSecSuccess }
        )
        #expect(created == false)
        #expect(KeyShareService.fingerprint(of: result.signingPublicKey)
                == KeyShareService.fingerprint(of: existing.publicKey))
    }

    @Test("resolveSigningIdentity: first create (no existing, add succeeds) uses fresh key")
    func resolveFirstCreate() throws {
        let fresh = P256.Signing.PrivateKey()
        let result = try KeyShareService.resolveSigningIdentity(
            load: { nil },
            create: { (.software(fresh), fresh.rawRepresentation) },
            add: { _ in errSecSuccess }
        )
        #expect(KeyShareService.fingerprint(of: result.signingPublicKey)
                == KeyShareService.fingerprint(of: fresh.publicKey))
    }

    @Test("resolveSigningIdentity: race (errSecDuplicateItem) adopts existing, never rotates")
    func resolveRaceAdoptsExisting() throws {
        let winner = P256.Signing.PrivateKey()   // 別スレッドが先に登録した鍵
        let loser = P256.Signing.PrivateKey()     // 自分が生成した鍵（捨てられるべき）
        var loads = 0
        let result = try KeyShareService.resolveSigningIdentity(
            load: {
                loads += 1
                // 1回目: まだ無い → nil、2回目: 先行書き込みが見える
                return loads == 1 ? nil : .software(winner)
            },
            create: { (.software(loser), loser.rawRepresentation) },
            add: { _ in errSecDuplicateItem }
        )
        // レース時は既存(winner)を採用し、フィンガープリントは安定（loser にならない）
        #expect(KeyShareService.fingerprint(of: result.signingPublicKey)
                == KeyShareService.fingerprint(of: winner.publicKey))
        #expect(KeyShareService.fingerprint(of: result.signingPublicKey)
                != KeyShareService.fingerprint(of: loser.publicKey))
        #expect(loads == 2)
    }

    @Test("resolveSigningIdentity: two sequential calls yield a stable fingerprint")
    func resolveStableAcrossCalls() throws {
        // 疑似的な単一エントリの Keychain をクロージャで再現
        var stored: (identity: SigningIdentity, blob: Data)?
        let load: () -> SigningIdentity? = { stored?.identity }
        let create: () throws -> (SigningIdentity, Data) = {
            let k = P256.Signing.PrivateKey()
            return (.software(k), k.rawRepresentation)
        }
        let add: (Data) -> OSStatus = { blob in
            if stored != nil { return errSecDuplicateItem }
            // create 済みの identity を stored に確定させる必要があるので、
            // ここでは blob から復元して格納する。
            if let k = try? P256.Signing.PrivateKey(rawRepresentation: blob) {
                stored = (.software(k), blob)
                return errSecSuccess
            }
            return errSecParam
        }
        let first = try KeyShareService.resolveSigningIdentity(load: load, create: create, add: add)
        let second = try KeyShareService.resolveSigningIdentity(load: load, create: create, add: add)
        #expect(KeyShareService.fingerprint(of: first.signingPublicKey)
                == KeyShareService.fingerprint(of: second.signingPublicKey))
    }

    // MARK: - #127 decodeSigningBlob ordering (deterministic backward-compat)

    @Test("decodeSigningBlob: 32B blob decodes as software (raw first), regardless of SE availability")
    func decode32ByteIsSoftware() {
        let sw = P256.Signing.PrivateKey()
        let raw = sw.rawRepresentation
        #expect(raw.count == 32)

        for seAvailable in [false, true] {
            let identity = KeyShareService.decodeSigningBlob(raw, seAvailable: seAvailable)
            #expect(identity?.isSecureEnclave == false)
            #expect(identity.map { KeyShareService.fingerprint(of: $0.signingPublicKey) }
                    == KeyShareService.fingerprint(of: sw.publicKey))
        }
    }

    @Test("decodeSigningBlob: >32B blob is never mis-decoded as software; SE only tried when available")
    func decodeOver32Byte() {
        // 32B 超のダミー blob（有効な SE blob ではない）。
        let bogus = Data(repeating: 0xAB, count: 91)
        // SE 非搭載: SE を試さず、software raw も 32B でないので失敗 → nil。
        #expect(KeyShareService.decodeSigningBlob(bogus, seAvailable: false) == nil)
        // SE 搭載でも不正 blob は SE init が失敗し、software raw も不成立 → nil。
        // （実 SE 生成は CI 不能だが、無効 blob は必ず nil に落ちる。）
        #expect(KeyShareService.decodeSigningBlob(bogus, seAvailable: true) == nil)
    }

    @Test("decodeSigningBlob: round-trips a freshly created SE identity when available")
    func decodeSERoundTrip() throws {
        let (identity, blob) = try KeyShareService.makeNewSigningIdentity()
        guard identity.isSecureEnclave else {
            // SE 非搭載 / 生成失敗環境ではスキップ相当（software は 32B テストで担保済み）。
            return
        }
        let decoded = KeyShareService.decodeSigningBlob(blob, seAvailable: true)
        #expect(decoded?.isSecureEnclave == true)
        #expect(decoded.map { KeyShareService.fingerprint(of: $0.signingPublicKey) }
                == KeyShareService.fingerprint(of: identity.signingPublicKey))
    }

    // MARK: - #127 SE abstraction / software path

    @Test("makeNewSigningIdentity produces a usable signer (SE or software)")
    func makeNewSigningIdentityUsable() throws {
        let (identity, blob) = try KeyShareService.makeNewSigningIdentity()
        #expect(!blob.isEmpty)
        let msg = Data("canonical-message".utf8)
        let sig = try identity.signRaw(msg)
        #expect(KeyShareService.verify(msg, signature: sig, publicKey: identity.signingPublicKey))
        // SE は CI で生成不能なことがあるため成否は問わない（フォールバックで software）。
        if !SecureEnclave.isAvailable {
            #expect(identity.isSecureEnclave == false)
            #expect(blob.count == 32) // software raw representation
        }
    }

    @Test("SigningIdentity.software goes through the same encrypt/verify path as a raw key")
    func softwareIdentityRoundTrip() throws {
        let recipient = P256.KeyAgreement.PrivateKey()
        let sw = P256.Signing.PrivateKey()
        let identity = SigningIdentity.software(sw)

        let file = try KeyShareService.makeEncryptedFile(
            keys: sampleKeys, recipientPublicKey: recipient.publicKey, signer: identity
        )
        #expect(file.version == 2)
        let share = try KeyShareService.decrypt(file: file, recipientPrivateKey: recipient)
        #expect(share.isAuthenticated == true)
        #expect(share.entries.map(\.value) == sampleKeys.map(\.value))
        // 抽象化しても指紋は素の鍵と一致（ローテーションしない）
        #expect(share.senderFingerprint == KeyShareService.fingerprint(of: sw.publicKey))
    }

    // MARK: - #126 TOFU store

    private func freshStore() -> FingerprintTOFUStore {
        let defaults = UserDefaults(suiteName: "tofu-test-\(UUID().uuidString)")!
        let store = FingerprintTOFUStore(defaults: defaults)
        store.reset()
        return store
    }

    @Test("TOFU: unknown fingerprint classifies as first-seen")
    func tofuFirstSeen() {
        let store = freshStore()
        defer { store.reset() }
        #expect(store.isEmpty)
        let fp = "1A2B 3C4D 5E6F"
        #expect(store.classify(fp) == .firstSeen)
        #expect(store.isKnown(fp) == false)
    }

    @Test("TOFU: confirm records fingerprint, then classifies as known")
    func tofuConfirmMakesKnown() {
        let store = freshStore()
        defer { store.reset() }
        let fp = "1A2B 3C4D 5E6F"
        let now = Date()
        store.confirm(fp, at: now)
        #expect(store.isKnown(fp) == true)
        #expect(store.isEmpty == false)
        if case .known(let since) = store.classify(fp) {
            #expect(abs(since.timeIntervalSince(now)) < 1)
        } else {
            Issue.record("expected .known after confirm")
        }
    }

    @Test("TOFU: re-confirm preserves the original firstSeen date")
    func tofuReconfirmPreservesFirstSeen() {
        let store = freshStore()
        defer { store.reset() }
        let fp = "DEAD BEEF"
        let first = Date(timeIntervalSince1970: 1_000_000)
        store.confirm(fp, at: first)
        store.confirm(fp, at: first.addingTimeInterval(99_999))
        let seen = store.firstSeen(fp)
        #expect(seen != nil)
        #expect(abs((seen ?? Date()).timeIntervalSince(first)) < 1)
    }

    @Test("TOFU: a new fingerprint is still first-seen even when the store is non-empty")
    func tofuNewFingerprintWhenNonEmpty() {
        let store = freshStore()
        defer { store.reset() }
        store.confirm("KNOWN AAAA")
        #expect(store.isEmpty == false)
        // 別の（新しい）フィンガープリント = 別の送信者 → 依然 first-seen
        #expect(store.classify("OTHER BBBB") == .firstSeen)
    }

    // MARK: - #126 freshness

    @Test("Freshness: recent createdAt is fresh, old is stale")
    func freshnessBasic() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let recent = now.addingTimeInterval(-3600) // 1h ago
        #expect(KeyShareService.classifyFreshness(createdAt: recent, now: now) == .fresh(age: 3600))

        let old = now.addingTimeInterval(-(31 * 24 * 3600)) // 31 days
        #expect(KeyShareService.classifyFreshness(createdAt: old, now: now).isStale)
    }

    @Test("Freshness: threshold boundary — exactly at threshold is fresh, just over is stale")
    func freshnessBoundary() {
        let now = Date(timeIntervalSinceReferenceDate: 2_000_000)
        let threshold = KeyShareService.stalenessThreshold

        let exactly = now.addingTimeInterval(-threshold)
        #expect(KeyShareService.classifyFreshness(createdAt: exactly, now: now).isStale == false)

        let justOver = now.addingTimeInterval(-(threshold + 1))
        #expect(KeyShareService.classifyFreshness(createdAt: justOver, now: now).isStale == true)
    }

    @Test("Freshness: a future createdAt is treated as fresh (non-stale)")
    func freshnessFutureDate() {
        let now = Date(timeIntervalSinceReferenceDate: 3_000_000)
        let future = now.addingTimeInterval(3600)
        let f = KeyShareService.classifyFreshness(createdAt: future, now: now)
        #expect(f.isStale == false)
        #expect(f.age < 0)
    }
}
