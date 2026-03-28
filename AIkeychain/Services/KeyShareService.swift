import Foundation
import CryptoKit

/// 公開鍵暗号方式による Keychain 共有サービス
/// P-256 + ECDH + AES-256-GCM
enum KeyShareService {

    private static let privateKeyTag = "com.aieo.aikeychain.sharekey"

    // MARK: - Key Pair Management

    /// 鍵ペアを生成して秘密鍵を Keychain に保存
    static func generateKeyPair() throws -> P256.KeyAgreement.PublicKey {
        let privateKey = P256.KeyAgreement.PrivateKey()

        // 秘密鍵を Keychain に保存
        try savePrivateKey(privateKey)

        return privateKey.publicKey
    }

    /// 秘密鍵が既に存在するか
    static func hasKeyPair() -> Bool {
        loadPrivateKey() != nil
    }

    /// 公開鍵を取得
    static func getPublicKey() -> P256.KeyAgreement.PublicKey? {
        loadPrivateKey()?.publicKey
    }

    /// 鍵ペアを削除
    static func deleteKeyPair() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: privateKeyTag,
            kSecAttrAccount as String: "private_key",
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Public Key Export/Import

    /// 公開鍵を .aikeychain-pub ファイルに書き出し
    static func exportPublicKey(to url: URL) throws {
        guard let publicKey = getPublicKey() else {
            throw ShareError.noKeyPair
        }

        let data = publicKey.x963Representation
        let encoded = ShareFileFormat.PublicKeyFile(
            version: 1,
            publicKey: data.base64EncodedString()
        )
        let json = try JSONEncoder().encode(encoded)
        try json.write(to: url)
    }

    /// .aikeychain-pub ファイルから公開鍵を読み込み
    static func importPublicKey(from url: URL) throws -> P256.KeyAgreement.PublicKey {
        let json = try Data(contentsOf: url)
        let file = try JSONDecoder().decode(ShareFileFormat.PublicKeyFile.self, from: json)

        guard let keyData = Data(base64Encoded: file.publicKey) else {
            throw ShareError.invalidPublicKey
        }

        return try P256.KeyAgreement.PublicKey(x963Representation: keyData)
    }

    // MARK: - Encrypt (送信者)

    /// 選択したキーを受信者の公開鍵で暗号化して .aikeychain ファイルに書き出し
    static func encryptAndExport(
        keys: [(envVarName: String, value: String)],
        recipientPublicKey: P256.KeyAgreement.PublicKey,
        to url: URL
    ) throws {
        // 1. エフェメラル鍵ペアを生成
        let ephemeralKey = P256.KeyAgreement.PrivateKey()

        // 2. ECDH で共有秘密を導出
        let sharedSecret = try ephemeralKey.sharedSecretFromKeyAgreement(with: recipientPublicKey)

        // 3. 共有秘密から対称鍵を導出
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("AIKeyChain-v1".utf8),
            sharedInfo: Data(),
            outputByteCount: 32
        )

        // 4. キーデータを JSON 化
        let payload = keys.map { ShareFileFormat.KeyEntry(envVarName: $0.envVarName, value: $0.value) }
        let plaintext = try JSONEncoder().encode(payload)

        // 5. AES-256-GCM で暗号化
        let sealedBox = try AES.GCM.seal(plaintext, using: symmetricKey)
        guard let combined = sealedBox.combined else {
            throw ShareError.encryptionFailed
        }

        // 6. ファイルに書き出し
        let file = ShareFileFormat.EncryptedFile(
            version: 1,
            ephemeralPublicKey: ephemeralKey.publicKey.x963Representation.base64EncodedString(),
            encryptedData: combined.base64EncodedString(),
            keyCount: keys.count
        )
        let json = try JSONEncoder().encode(file)
        try json.write(to: url)
    }

    // MARK: - Decrypt (受信者)

    /// .aikeychain ファイルを自分の秘密鍵で復号
    static func decryptAndImport(from url: URL) throws -> [(envVarName: String, value: String)] {
        guard let privateKey = loadPrivateKey() else {
            throw ShareError.noKeyPair
        }

        // 1. ファイル読み込み
        let json = try Data(contentsOf: url)
        let file = try JSONDecoder().decode(ShareFileFormat.EncryptedFile.self, from: json)

        // 2. エフェメラル公開鍵を復元
        guard let ephemeralKeyData = Data(base64Encoded: file.ephemeralPublicKey) else {
            throw ShareError.invalidFile
        }
        let ephemeralPublicKey = try P256.KeyAgreement.PublicKey(x963Representation: ephemeralKeyData)

        // 3. ECDH で共有秘密を導出
        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: ephemeralPublicKey)

        // 4. 対称鍵を導出
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("AIKeyChain-v1".utf8),
            sharedInfo: Data(),
            outputByteCount: 32
        )

        // 5. 復号
        guard let encryptedData = Data(base64Encoded: file.encryptedData) else {
            throw ShareError.invalidFile
        }
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        let plaintext = try AES.GCM.open(sealedBox, using: symmetricKey)

        // 6. キーデータをパース
        let entries = try JSONDecoder().decode([ShareFileFormat.KeyEntry].self, from: plaintext)
        return entries.map { ($0.envVarName, $0.value) }
    }

    // MARK: - Private Key Storage

    private static func savePrivateKey(_ key: P256.KeyAgreement.PrivateKey) throws {
        let rawKey = key.rawRepresentation

        // 既存を削除
        deleteKeyPair()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: privateKeyTag,
            kSecAttrAccount as String: "private_key",
            kSecValueData as String: rawKey,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw ShareError.keychainError(status)
        }
    }

    private static func loadPrivateKey() -> P256.KeyAgreement.PrivateKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: privateKeyTag,
            kSecAttrAccount as String: "private_key",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return nil }

        return try? P256.KeyAgreement.PrivateKey(rawRepresentation: data)
    }

    // MARK: - Errors

    enum ShareError: LocalizedError {
        case noKeyPair
        case invalidPublicKey
        case invalidFile
        case encryptionFailed
        case keychainError(OSStatus)

        var errorDescription: String? {
            switch self {
            case .noKeyPair: "No key pair found. Generate one first."
            case .invalidPublicKey: "Invalid public key file."
            case .invalidFile: "Invalid or corrupted .aikeychain file."
            case .encryptionFailed: "Encryption failed."
            case .keychainError(let s): "Keychain error: \(s)"
            }
        }
    }
}

// MARK: - File Format

enum ShareFileFormat {
    struct PublicKeyFile: Codable {
        let version: Int
        let publicKey: String // base64 x963
    }

    struct EncryptedFile: Codable {
        let version: Int
        let ephemeralPublicKey: String // base64 x963
        let encryptedData: String      // base64 AES-GCM sealed box
        let keyCount: Int
    }

    struct KeyEntry: Codable {
        let envVarName: String
        let value: String
    }
}
