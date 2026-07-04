import Foundation
import CryptoKit
import Testing
@testable import AIkeychain

/// #112 送信者認証（署名 + フィンガープリント + v2 フォーマット）
///
/// Keychain に触れずにテストできるよう、鍵はメモリ上に生成し、
/// pure な makeEncryptedFile / decrypt / canonicalMessage / fingerprint を直接叩く。
@Suite("KeyShareService Sender Auth (#112)")
struct KeyShareServiceTests {

    private let sampleKeys: [(envVarName: String, value: String)] = [
        ("OPENAI_API_KEY", "sk-test-value-1234567890abcdef"),
        ("GITHUB_TOKEN", "ghp_abcdefghijklmnopqrstuvwxyz0123456789"),
    ]

    // MARK: v2 round trip

    @Test("v2 round trip: encrypt (sender) → decrypt (recipient) authenticates and matches")
    func v2RoundTrip() throws {
        let recipient = P256.KeyAgreement.PrivateKey()
        let signing = P256.Signing.PrivateKey()

        let file = try KeyShareService.makeEncryptedFile(
            keys: sampleKeys,
            recipientPublicKey: recipient.publicKey,
            signingPrivateKey: signing
        )
        #expect(file.version == 2)
        #expect(file.signature != nil)
        #expect(file.senderSigningPublicKey != nil)
        #expect(file.createdAt != nil)

        let share = try KeyShareService.decrypt(file: file, recipientPrivateKey: recipient)
        #expect(share.isAuthenticated == true)
        #expect(share.entries.count == sampleKeys.count)
        #expect(share.entries.map(\.envVarName) == sampleKeys.map(\.envVarName))
        #expect(share.entries.map(\.value) == sampleKeys.map(\.value))
        #expect(share.senderFingerprint == KeyShareService.fingerprint(of: signing.publicKey))
        #expect(share.createdAt != nil)
    }

    // MARK: Tamper detection

    @Test("Tampering with encryptedData throws signatureInvalid")
    func tamperEncryptedData() throws {
        let recipient = P256.KeyAgreement.PrivateKey()
        let signing = P256.Signing.PrivateKey()
        let file = try KeyShareService.makeEncryptedFile(
            keys: sampleKeys, recipientPublicKey: recipient.publicKey, signingPrivateKey: signing
        )

        // 別の暗号文（有効な base64）に差し替える
        let other = try KeyShareService.makeEncryptedFile(
            keys: [("X", "yyyyyyyyyyyyyyyyyy")], recipientPublicKey: recipient.publicKey, signingPrivateKey: signing
        )
        let tampered = ShareFileFormat.EncryptedFile(
            version: file.version,
            ephemeralPublicKey: file.ephemeralPublicKey,
            encryptedData: other.encryptedData,   // ← 改ざん
            keyCount: file.keyCount,
            senderSigningPublicKey: file.senderSigningPublicKey,
            signature: file.signature,
            createdAt: file.createdAt
        )

        #expect(throws: KeyShareService.ShareError.signatureInvalid) {
            _ = try KeyShareService.decrypt(file: tampered, recipientPrivateKey: recipient)
        }
    }

    @Test("Tampering with keyCount throws signatureInvalid")
    func tamperKeyCount() throws {
        let recipient = P256.KeyAgreement.PrivateKey()
        let signing = P256.Signing.PrivateKey()
        let file = try KeyShareService.makeEncryptedFile(
            keys: sampleKeys, recipientPublicKey: recipient.publicKey, signingPrivateKey: signing
        )
        let tampered = ShareFileFormat.EncryptedFile(
            version: file.version,
            ephemeralPublicKey: file.ephemeralPublicKey,
            encryptedData: file.encryptedData,
            keyCount: file.keyCount + 99,          // ← 改ざん
            senderSigningPublicKey: file.senderSigningPublicKey,
            signature: file.signature,
            createdAt: file.createdAt
        )
        #expect(throws: KeyShareService.ShareError.signatureInvalid) {
            _ = try KeyShareService.decrypt(file: tampered, recipientPrivateKey: recipient)
        }
    }

    @Test("Swapping senderSigningPublicKey (with unchanged signature) throws signatureInvalid")
    func tamperSenderKey() throws {
        let recipient = P256.KeyAgreement.PrivateKey()
        let signing = P256.Signing.PrivateKey()
        let file = try KeyShareService.makeEncryptedFile(
            keys: sampleKeys, recipientPublicKey: recipient.publicKey, signingPrivateKey: signing
        )
        let attackerKey = P256.Signing.PrivateKey()
        let tampered = ShareFileFormat.EncryptedFile(
            version: file.version,
            ephemeralPublicKey: file.ephemeralPublicKey,
            encryptedData: file.encryptedData,
            keyCount: file.keyCount,
            senderSigningPublicKey: attackerKey.publicKey.x963Representation.base64EncodedString(), // ← 改ざん
            signature: file.signature,
            createdAt: file.createdAt
        )
        #expect(throws: KeyShareService.ShareError.signatureInvalid) {
            _ = try KeyShareService.decrypt(file: tampered, recipientPrivateKey: recipient)
        }
    }

    @Test("Tampering with createdAt throws signatureInvalid")
    func tamperCreatedAt() throws {
        let recipient = P256.KeyAgreement.PrivateKey()
        let signing = P256.Signing.PrivateKey()
        let file = try KeyShareService.makeEncryptedFile(
            keys: sampleKeys, recipientPublicKey: recipient.publicKey, signingPrivateKey: signing
        )
        let tampered = ShareFileFormat.EncryptedFile(
            version: file.version,
            ephemeralPublicKey: file.ephemeralPublicKey,
            encryptedData: file.encryptedData,
            keyCount: file.keyCount,
            senderSigningPublicKey: file.senderSigningPublicKey,
            signature: file.signature,
            createdAt: "2000-01-01T00:00:00Z"        // ← 改ざん
        )
        #expect(throws: KeyShareService.ShareError.signatureInvalid) {
            _ = try KeyShareService.decrypt(file: tampered, recipientPrivateKey: recipient)
        }
    }

    // MARK: fail-closed structural checks (#112 Fable review)

    @Test("Signature-stripping (drop sig fields from a v2 file) throws signatureInvalid")
    func signatureStripping() throws {
        let recipient = P256.KeyAgreement.PrivateKey()
        let signing = P256.Signing.PrivateKey()
        let file = try KeyShareService.makeEncryptedFile(
            keys: sampleKeys, recipientPublicKey: recipient.publicKey, signingPrivateKey: signing
        )
        // version は 2 のまま署名フィールドを除去 → strip 攻撃
        let stripped = ShareFileFormat.EncryptedFile(
            version: 2,
            ephemeralPublicKey: file.ephemeralPublicKey,
            encryptedData: file.encryptedData,
            keyCount: file.keyCount,
            senderSigningPublicKey: nil,
            signature: nil,
            createdAt: file.createdAt
        )
        #expect(throws: KeyShareService.ShareError.signatureInvalid) {
            _ = try KeyShareService.decrypt(file: stripped, recipientPrivateKey: recipient)
        }
    }

    @Test("Version downgrade 2→1 while keeping signature throws signatureInvalid")
    func versionDowngrade() throws {
        let recipient = P256.KeyAgreement.PrivateKey()
        let signing = P256.Signing.PrivateKey()
        let file = try KeyShareService.makeEncryptedFile(
            keys: sampleKeys, recipientPublicKey: recipient.publicKey, signingPrivateKey: signing
        )
        // version を 1 に書き換え（署名は残す）→ 正規メッセージの version が食い違い署名不一致
        let downgraded = ShareFileFormat.EncryptedFile(
            version: 1,
            ephemeralPublicKey: file.ephemeralPublicKey,
            encryptedData: file.encryptedData,
            keyCount: file.keyCount,
            senderSigningPublicKey: file.senderSigningPublicKey,
            signature: file.signature,
            createdAt: file.createdAt
        )
        #expect(throws: KeyShareService.ShareError.signatureInvalid) {
            _ = try KeyShareService.decrypt(file: downgraded, recipientPrivateKey: recipient)
        }
    }

    @Test("Structural inconsistency: only one of signature/senderSigningPublicKey present throws signatureInvalid")
    func inconsistentSignatureFields() throws {
        let recipient = P256.KeyAgreement.PrivateKey()
        let signing = P256.Signing.PrivateKey()
        let file = try KeyShareService.makeEncryptedFile(
            keys: sampleKeys, recipientPublicKey: recipient.publicKey, signingPrivateKey: signing
        )
        // signature だけ present（senderSigningPublicKey を落とす）
        let onlySig = ShareFileFormat.EncryptedFile(
            version: file.version,
            ephemeralPublicKey: file.ephemeralPublicKey,
            encryptedData: file.encryptedData,
            keyCount: file.keyCount,
            senderSigningPublicKey: nil,
            signature: file.signature,
            createdAt: file.createdAt
        )
        #expect(throws: KeyShareService.ShareError.signatureInvalid) {
            _ = try KeyShareService.decrypt(file: onlySig, recipientPrivateKey: recipient)
        }
        // senderSigningPublicKey だけ present（signature を落とす）
        let onlyKey = ShareFileFormat.EncryptedFile(
            version: file.version,
            ephemeralPublicKey: file.ephemeralPublicKey,
            encryptedData: file.encryptedData,
            keyCount: file.keyCount,
            senderSigningPublicKey: file.senderSigningPublicKey,
            signature: nil,
            createdAt: file.createdAt
        )
        #expect(throws: KeyShareService.ShareError.signatureInvalid) {
            _ = try KeyShareService.decrypt(file: onlyKey, recipientPrivateKey: recipient)
        }
    }

    @Test("Unknown version is rejected (invalidFile)")
    func unknownVersion() throws {
        let recipient = P256.KeyAgreement.PrivateKey()
        let signing = P256.Signing.PrivateKey()
        let file = try KeyShareService.makeEncryptedFile(
            keys: sampleKeys, recipientPublicKey: recipient.publicKey, signingPrivateKey: signing
        )
        let future = ShareFileFormat.EncryptedFile(
            version: 99,
            ephemeralPublicKey: file.ephemeralPublicKey,
            encryptedData: file.encryptedData,
            keyCount: file.keyCount,
            senderSigningPublicKey: file.senderSigningPublicKey,
            signature: file.signature,
            createdAt: file.createdAt
        )
        #expect(throws: KeyShareService.ShareError.invalidFile) {
            _ = try KeyShareService.decrypt(file: future, recipientPrivateKey: recipient)
        }
    }

    @Test("Attribution swap: re-sign with attacker key over another's ciphertext fails GCM decryption")
    func attributionSwap() throws {
        let recipient = P256.KeyAgreement.PrivateKey()
        let sender = P256.Signing.PrivateKey()
        let legit = try KeyShareService.makeEncryptedFile(
            keys: sampleKeys, recipientPublicKey: recipient.publicKey, signingPrivateKey: sender
        )
        // 攻撃者は他人の暗号文をそのまま流用し、senderSigningPublicKey を自分の鍵に
        // 差し替えて「自分の鍵で有効に署名し直す」。署名検証は通ってしまうが、
        // HKDF sharedInfo が送信者署名公開鍵に束縛されているため、対称鍵が食い違い
        // GCM 復号自体が失敗する。
        let attacker = P256.Signing.PrivateKey()
        let attackerPubB64 = attacker.publicKey.x963Representation.base64EncodedString()
        let message = KeyShareService.canonicalMessage(
            version: legit.version,
            ephemeralPublicKeyB64: legit.ephemeralPublicKey,
            encryptedDataB64: legit.encryptedData,
            keyCount: legit.keyCount,
            senderSigningPublicKeyB64: attackerPubB64,
            createdAt: legit.createdAt ?? ""
        )
        let attackerSig = try KeyShareService.signMessage(message, with: attacker).base64EncodedString()
        let swapped = ShareFileFormat.EncryptedFile(
            version: legit.version,
            ephemeralPublicKey: legit.ephemeralPublicKey,
            encryptedData: legit.encryptedData,
            keyCount: legit.keyCount,
            senderSigningPublicKey: attackerPubB64,
            signature: attackerSig,
            createdAt: legit.createdAt
        )
        #expect(throws: (any Error).self) {
            _ = try KeyShareService.decrypt(file: swapped, recipientPrivateKey: recipient)
        }
    }

    @Test("Empty key list round trip")
    func emptyRoundTrip() throws {
        let recipient = P256.KeyAgreement.PrivateKey()
        let signing = P256.Signing.PrivateKey()
        let file = try KeyShareService.makeEncryptedFile(
            keys: [], recipientPublicKey: recipient.publicKey, signingPrivateKey: signing
        )
        #expect(file.keyCount == 0)
        let share = try KeyShareService.decrypt(file: file, recipientPrivateKey: recipient)
        #expect(share.isAuthenticated == true)
        #expect(share.entries.isEmpty)
    }

    // MARK: Forgery-with-different-key

    @Test("Forgery with a different signing key verifies but yields a DIFFERENT fingerprint")
    func forgeryDifferentKey() throws {
        let recipient = P256.KeyAgreement.PrivateKey()
        let expectedSender = P256.Signing.PrivateKey()
        let attacker = P256.Signing.PrivateKey()

        // 攻撃者は自分の署名鍵で完全に有効なファイルを作れる
        let forged = try KeyShareService.makeEncryptedFile(
            keys: [("OPENAI_API_KEY", "sk-attacker-substituted-value-000")],
            recipientPublicKey: recipient.publicKey,
            signingPrivateKey: attacker
        )
        let share = try KeyShareService.decrypt(file: forged, recipientPrivateKey: recipient)

        // 署名としては有効（isAuthenticated=true）だが、指紋が期待送信者と異なる
        #expect(share.isAuthenticated == true)
        #expect(share.senderFingerprint == KeyShareService.fingerprint(of: attacker.publicKey))
        #expect(share.senderFingerprint != KeyShareService.fingerprint(of: expectedSender.publicKey))
    }

    // MARK: v1 backward compatibility

    @Test("Hand-constructed v1 file (no signature fields) decodes, decrypts, unauthenticated")
    func v1BackwardCompat() throws {
        let recipient = P256.KeyAgreement.PrivateKey()

        // v1 相当の暗号文をその場で生成（署名なし・追加フィールドなしの JSON）
        let ephemeral = P256.KeyAgreement.PrivateKey()
        let shared = try ephemeral.sharedSecretFromKeyAgreement(with: recipient.publicKey)
        let symKey = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self, salt: Data("AIKeyChain-v1".utf8), sharedInfo: Data(), outputByteCount: 32
        )
        let payload = sampleKeys.map { ShareFileFormat.KeyEntry(envVarName: $0.envVarName, value: $0.value) }
        let plaintext = try JSONEncoder().encode(payload)
        let combined = try AES.GCM.seal(plaintext, using: symKey).combined!

        // 追加フィールドを含まない v1 JSON を手で組む
        let v1Json = """
        {
          "version": 1,
          "ephemeralPublicKey": "\(ephemeral.publicKey.x963Representation.base64EncodedString())",
          "encryptedData": "\(combined.base64EncodedString())",
          "keyCount": \(sampleKeys.count)
        }
        """
        let file = try JSONDecoder().decode(ShareFileFormat.EncryptedFile.self, from: Data(v1Json.utf8))
        #expect(file.signature == nil)
        #expect(file.senderSigningPublicKey == nil)
        #expect(file.createdAt == nil)

        let share = try KeyShareService.decrypt(file: file, recipientPrivateKey: recipient)
        #expect(share.isAuthenticated == false)
        #expect(share.senderFingerprint == nil)
        #expect(share.entries.map(\.envVarName) == sampleKeys.map(\.envVarName))
        #expect(share.entries.map(\.value) == sampleKeys.map(\.value))
    }

    // MARK: Fingerprint

    @Test("Fingerprint is full-length (256-bit) and stable for the same key")
    func fingerprintFullLength() {
        let key = P256.Signing.PrivateKey()
        let fp = KeyShareService.fingerprint(of: key.publicKey)

        // 64 hex chars (256-bit) grouped in 4 => 16 groups, 15 spaces
        let hexOnly = fp.replacingOccurrences(of: " ", with: "")
        #expect(hexOnly.count == 64) // 32 bytes * 2 — NOT truncated to 64-bit (16 chars)
        #expect(hexOnly.allSatisfy { $0.isHexDigit && ($0.isNumber || $0.isUppercase) })
        #expect(fp.split(separator: " ").count == 16)

        // Stable
        #expect(KeyShareService.fingerprint(of: key.publicKey) == fp)

        // Distinct keys differ
        let other = P256.Signing.PrivateKey()
        #expect(KeyShareService.fingerprint(of: other.publicKey) != fp)
    }

    // MARK: Canonical message

    @Test("canonicalMessage is deterministic and field-order sensitive")
    func canonicalDeterministic() {
        let a = KeyShareService.canonicalMessage(
            version: 2, ephemeralPublicKeyB64: "AAA", encryptedDataB64: "BBB",
            keyCount: 3, senderSigningPublicKeyB64: "CCC", createdAt: "2026-07-04T00:00:00Z"
        )
        let same = KeyShareService.canonicalMessage(
            version: 2, ephemeralPublicKeyB64: "AAA", encryptedDataB64: "BBB",
            keyCount: 3, senderSigningPublicKeyB64: "CCC", createdAt: "2026-07-04T00:00:00Z"
        )
        let diff = KeyShareService.canonicalMessage(
            version: 2, ephemeralPublicKeyB64: "AAA", encryptedDataB64: "BBB",
            keyCount: 4, senderSigningPublicKeyB64: "CCC", createdAt: "2026-07-04T00:00:00Z"
        )
        #expect(a == same)
        #expect(a != diff)
    }

    @Test("sign / verify round trip over canonical message")
    func signVerify() throws {
        let signing = P256.Signing.PrivateKey()
        let msg = KeyShareService.canonicalMessage(
            version: 2, ephemeralPublicKeyB64: "AAA", encryptedDataB64: "BBB",
            keyCount: 1, senderSigningPublicKeyB64: "CCC", createdAt: "2026-07-04T00:00:00Z"
        )
        let sig = try KeyShareService.signMessage(msg, with: signing)
        #expect(KeyShareService.verify(msg, signature: sig, publicKey: signing.publicKey) == true)

        let otherKey = P256.Signing.PrivateKey()
        #expect(KeyShareService.verify(msg, signature: sig, publicKey: otherKey.publicKey) == false)

        // Garbage signature bytes verify false, not crash
        #expect(KeyShareService.verify(msg, signature: Data([0x00, 0x01]), publicKey: signing.publicKey) == false)
    }
}
