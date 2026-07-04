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

        #expect(throws: KeyShareService.ShareError.self) {
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
        #expect(throws: KeyShareService.ShareError.self) {
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
        #expect(throws: KeyShareService.ShareError.self) {
            _ = try KeyShareService.decrypt(file: tampered, recipientPrivateKey: recipient)
        }
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
