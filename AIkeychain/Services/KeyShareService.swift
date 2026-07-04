import Foundation
import CryptoKit
import Security

/// 公開鍵暗号方式による Keychain 共有サービス
/// P-256 + ECDH + AES-256-GCM（機密性）に加え、
/// P-256 ECDSA 署名（送信者認証・完全性）を付与する。
///
/// 脅威モデル: 受信者の公開鍵は共有される前提のため、暗号化だけでは
/// 「復号できた＝正しい送信者が作った」とは言えない。公開鍵を持つ第三者は
/// 完全に有効な `.aikeychain` を偽造でき、受信者に攻撃者が選んだキー値を
/// 掴ませる（credential substitution）ことが可能。これを防ぐため送信者の
/// 署名鍵で正規メッセージに署名し、受信者はフィンガープリントを帯域外で
/// 照合する（有効な署名 ≠ 信頼できる送信者。UI がこの照合を強制する）。
enum KeyShareService {

    private static let privateKeyTag = "com.aieo.aikeychain.sharekey"
    private static let signKeyTag = "com.aieo.aikeychain.signkey"

    /// createdAt の直列化に使う ISO8601 フォーマッタ（正規メッセージにも埋め込む）。
    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // MARK: - Key Pair Management

    /// 鍵ペア（鍵共有 + 署名）を生成して秘密鍵を Keychain に保存
    static func generateKeyPair() throws -> P256.KeyAgreement.PublicKey {
        let privateKey = P256.KeyAgreement.PrivateKey()

        // 秘密鍵を Keychain に保存
        try savePrivateKey(privateKey)

        // 署名鍵も同時に用意する
        _ = try ensureSigningKey()

        return privateKey.publicKey
    }

    /// 秘密鍵（鍵共有）が既に存在するか
    static func hasKeyPair() -> Bool {
        loadPrivateKey() != nil
    }

    /// 公開鍵（鍵共有）を取得
    static func getPublicKey() -> P256.KeyAgreement.PublicKey? {
        loadPrivateKey()?.publicKey
    }

    /// 鍵ペアを削除（鍵共有 + 署名の両方）
    static func deleteKeyPair() {
        for (service, account) in [(privateKeyTag, "private_key"), (signKeyTag, "signing_key")] {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            SecItemDelete(query as CFDictionary)
        }
    }

    // MARK: - Signing Identity

    /// 署名鍵を取得（無ければ生成して保存 = 既存ユーザーにも透過的に付与）。
    /// 返り値は SE / ソフトウェアを隠蔽する `SigningIdentity`。
    @discardableResult
    static func ensureSigningKey() throws -> SigningIdentity {
        try resolveSigningIdentity(
            load: { loadSigningIdentity() },
            create: { try makeNewSigningIdentity() },
            add: { addSigningBlob($0) }
        )
    }

    /// get-or-create の純粋（テスト可能）な解決ロジック。Keychain 非依存。
    ///
    /// レース解消（#127）: `add` が `errSecDuplicateItem` を返した場合は、
    /// 別スレッド／別プロセスが先に鍵を作成したとみなし、**既存を再読込して採用**する。
    /// 決して上書き（＝フィンガープリントのローテーション）はしない。
    static func resolveSigningIdentity(
        load: () -> SigningIdentity?,
        create: () throws -> (identity: SigningIdentity, blob: Data),
        add: (Data) -> OSStatus
    ) throws -> SigningIdentity {
        if let existing = load() { return existing }
        let fresh = try create()
        let status = add(fresh.blob)
        switch status {
        case errSecSuccess:
            return fresh.identity
        case errSecDuplicateItem:
            // レース: 先行書き込みが勝った。既存を採用し、自分の新規鍵は捨てる。
            if let existing = load() { return existing }
            throw ShareError.keychainError(status)
        default:
            throw ShareError.keychainError(status)
        }
    }

    /// 新しい署名アイデンティティを生成する。
    /// SE が利用可能なら Secure Enclave 鍵（`dataRepresentation` は不透明ブロブ）、
    /// 無ければ従来のソフトウェア P256 鍵（`rawRepresentation`）を作る。
    static func makeNewSigningIdentity() throws -> (identity: SigningIdentity, blob: Data) {
        if SecureEnclave.isAvailable {
            // .privateKeyUsage + AfterFirstUnlockThisDeviceOnly のアクセス制御を付与。
            var acError: Unmanaged<CFError>?
            if let access = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                [.privateKeyUsage],
                &acError
            ), let seKey = try? SecureEnclave.P256.Signing.PrivateKey(accessControl: access) {
                return (.secureEnclave(seKey), seKey.dataRepresentation)
            }
            // SE 生成に失敗したらソフトウェアへフォールバック（可用性優先）。
        }
        let sw = P256.Signing.PrivateKey()
        return (.software(sw), sw.rawRepresentation)
    }

    /// 署名用公開鍵を取得（存在する場合のみ。無ければ nil）
    static func getSigningPublicKey() -> P256.Signing.PublicKey? {
        loadSigningIdentity()?.signingPublicKey
    }

    /// 自分の署名フィンガープリント（無ければ生成して算出）
    static func ownSigningFingerprint() -> String? {
        guard let identity = try? ensureSigningKey() else { return nil }
        return fingerprint(of: identity.signingPublicKey)
    }

    /// 署名公開鍵の SHA256(x963) を 256bit フル長で、4桁ずつスペース区切りの
    /// 大文字16進として返す（例: "1A2B 3C4D ..."）。64bit などに切り詰めない。
    static func fingerprint(of signingPublicKey: P256.Signing.PublicKey) -> String {
        let hash = SHA256.hash(data: signingPublicKey.x963Representation)
        let hex = hash.map { String(format: "%02X", $0) }.joined()
        var groups: [String] = []
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let end = hex.index(idx, offsetBy: 4, limitedBy: hex.endIndex) ?? hex.endIndex
            groups.append(String(hex[idx..<end]))
            idx = end
        }
        return groups.joined(separator: " ")
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

    // MARK: - Canonical Signed Message (pure / testable)

    /// 署名対象の正規（canonical）メッセージを構築する。
    ///
    /// バイト列レイアウト（UTF-8、フィールドは固定順、`\n`(0x0A) 区切り、末尾改行なし）:
    /// ```
    /// AIKEYCHAIN-SHARE-SIG-V1\n
    /// version:<version>\n
    /// ephemeralPublicKey:<base64 x963>\n
    /// encryptedData:<base64 sealed box>\n
    /// keyCount:<int>\n
    /// senderSigningPublicKey:<base64 x963>\n
    /// createdAt:<ISO8601>
    /// ```
    /// base64 アルファベット（A-Za-z0-9+/=）は `:` も `\n` も含まないため、
    /// フィールド境界は一意に定まる。createdAt は `:` を含むが最終フィールドなので曖昧さは無い。
    /// 署名検証時は、パース済みの各フィールドから同一のバイト列を再構築して照合する。
    static func canonicalMessage(
        version: Int,
        ephemeralPublicKeyB64: String,
        encryptedDataB64: String,
        keyCount: Int,
        senderSigningPublicKeyB64: String,
        createdAt: String
    ) -> Data {
        let s = """
        AIKEYCHAIN-SHARE-SIG-V1
        version:\(version)
        ephemeralPublicKey:\(ephemeralPublicKeyB64)
        encryptedData:\(encryptedDataB64)
        keyCount:\(keyCount)
        senderSigningPublicKey:\(senderSigningPublicKeyB64)
        createdAt:\(createdAt)
        """
        return Data(s.utf8)
    }

    /// ECDH 共有秘密から AES-256-GCM 用の対称鍵を導出する。
    /// `sharedInfo` は v2 で送信者署名公開鍵に束縛される（v1 は空）。salt は固定。
    private static func deriveSymmetricKey(from sharedSecret: SharedSecret, sharedInfo: Data) -> SymmetricKey {
        sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("AIKeyChain-v1".utf8),
            sharedInfo: sharedInfo,
            outputByteCount: 32
        )
    }

    /// 正規メッセージへ署名し rawRepresentation を返す（純粋・鍵引数）
    static func signMessage(_ message: Data, with signingKey: P256.Signing.PrivateKey) throws -> Data {
        try signingKey.signature(for: message).rawRepresentation
    }

    /// 署名を検証（純粋・鍵引数）。壊れた署名バイト列は false を返す。
    static func verify(_ message: Data, signature: Data, publicKey: P256.Signing.PublicKey) -> Bool {
        guard let sig = try? P256.Signing.ECDSASignature(rawRepresentation: signature) else {
            return false
        }
        return publicKey.isValidSignature(sig, for: message)
    }

    // MARK: - Freshness (#126, pure / testable)

    /// 署名済み `createdAt` の鮮度分類。しきい値より古いものは replay（古い署名済み
    /// ファイルを、既にローテーション済みの鍵で再送）の疑いとして stale とする。
    enum Freshness: Equatable {
        case fresh(age: TimeInterval)
        case stale(age: TimeInterval)

        var age: TimeInterval {
            switch self {
            case .fresh(let a), .stale(let a): return a
            }
        }
        var isStale: Bool {
            if case .stale = self { return true }
            return false
        }
    }

    /// 既定の陳腐化しきい値（30 日）。
    static let stalenessThreshold: TimeInterval = 30 * 24 * 60 * 60

    /// `createdAt` の鮮度を分類する純粋関数（基準時刻を引数で受け取りテスト可能）。
    /// age は `now - createdAt`。しきい値超過で stale。未来日付（負の age）は fresh 扱い。
    static func classifyFreshness(
        createdAt: Date,
        now: Date = Date(),
        threshold: TimeInterval = stalenessThreshold
    ) -> Freshness {
        let age = now.timeIntervalSince(createdAt)
        return age > threshold ? .stale(age: age) : .fresh(age: age)
    }

    // MARK: - Encrypt (送信者)

    /// 暗号化 + 署名済みの EncryptedFile を構築する（純粋・鍵引数。Keychain 非依存）。
    /// ソフトウェア鍵版（既存テスト・呼び出し互換）。内部で汎用実装へ委譲する。
    static func makeEncryptedFile(
        keys: [(envVarName: String, value: String)],
        recipientPublicKey: P256.KeyAgreement.PublicKey,
        signingPrivateKey: P256.Signing.PrivateKey,
        createdAt: Date = Date()
    ) throws -> ShareFileFormat.EncryptedFile {
        try makeEncryptedFile(
            keys: keys,
            recipientPublicKey: recipientPublicKey,
            signer: signingPrivateKey,
            createdAt: createdAt
        )
    }

    /// 暗号化 + 署名済みの EncryptedFile を構築する（汎用版）。
    /// 署名は `MessageSigner` に抽象化されており、SE / ソフトウェアどちらでも同一経路。
    static func makeEncryptedFile<S: MessageSigner>(
        keys: [(envVarName: String, value: String)],
        recipientPublicKey: P256.KeyAgreement.PublicKey,
        signer: S,
        createdAt: Date = Date()
    ) throws -> ShareFileFormat.EncryptedFile {
        // 1. エフェメラル鍵ペアを生成
        let ephemeralKey = P256.KeyAgreement.PrivateKey()

        // 2. ECDH で共有秘密を導出
        let sharedSecret = try ephemeralKey.sharedSecretFromKeyAgreement(with: recipientPublicKey)

        // 3. 送信者署名公開鍵を HKDF の sharedInfo に束縛して対称鍵を導出（v2）。
        //    こうすると senderSigningPublicKey を後から差し替えると GCM 復号自体が
        //    失敗するため、他人の暗号文を自分の鍵で「再署名」して自分のものとして
        //    提示する attribution swap を防げる。送信者は自分の署名鍵を知っているので
        //    この sharedInfo を導出できる。
        let signPubData = signer.signingPublicKey.x963Representation
        let symmetricKey = deriveSymmetricKey(from: sharedSecret, sharedInfo: signPubData)

        // 4. キーデータを JSON 化
        let payload = keys.map { ShareFileFormat.KeyEntry(envVarName: $0.envVarName, value: $0.value) }
        let plaintext = try JSONEncoder().encode(payload)

        // 5. AES-256-GCM で暗号化
        let sealedBox = try AES.GCM.seal(plaintext, using: symmetricKey)
        guard let combined = sealedBox.combined else {
            throw ShareError.encryptionFailed
        }

        // 6. 正規メッセージへ署名（v2）
        let version = 2
        let ephB64 = ephemeralKey.publicKey.x963Representation.base64EncodedString()
        let encB64 = combined.base64EncodedString()
        let signPubB64 = signPubData.base64EncodedString()
        let createdAtStr = iso8601.string(from: createdAt)

        let message = canonicalMessage(
            version: version,
            ephemeralPublicKeyB64: ephB64,
            encryptedDataB64: encB64,
            keyCount: keys.count,
            senderSigningPublicKeyB64: signPubB64,
            createdAt: createdAtStr
        )
        let signature = try signer.signRaw(message)

        return ShareFileFormat.EncryptedFile(
            version: version,
            ephemeralPublicKey: ephB64,
            encryptedData: encB64,
            keyCount: keys.count,
            senderSigningPublicKey: signPubB64,
            signature: signature.base64EncodedString(),
            createdAt: createdAtStr
        )
    }

    /// 選択したキーを受信者の公開鍵で暗号化し、自分の署名鍵で署名して
    /// .aikeychain ファイル(v2)に書き出し
    static func encryptAndExport(
        keys: [(envVarName: String, value: String)],
        recipientPublicKey: P256.KeyAgreement.PublicKey,
        to url: URL
    ) throws {
        let signingKey = try ensureSigningKey()
        let file = try makeEncryptedFile(
            keys: keys,
            recipientPublicKey: recipientPublicKey,
            signer: signingKey
        )
        let json = try JSONEncoder().encode(file)
        try json.write(to: url)
    }

    // MARK: - Decrypt (受信者)

    /// 復号結果 + 送信者認証情報
    struct DecryptedShare {
        let entries: [(envVarName: String, value: String)]
        let senderFingerprint: String?
        let isAuthenticated: Bool
        let createdAt: Date?
    }

    /// EncryptedFile を受信者秘密鍵で復号し、v2 なら署名を検証する（純粋・鍵引数。Keychain 非依存）。
    static func decrypt(
        file: ShareFileFormat.EncryptedFile,
        recipientPrivateKey: P256.KeyAgreement.PrivateKey
    ) throws -> DecryptedShare {
        // 0. バージョン & 構造整合性チェック（crypto 層で fail-closed）。
        //    この関数は GUI 以外（将来 CLI 等）からも再利用される想定のため、
        //    人間ゲートに依存せずここで不整合を弾く。
        //    - 未知バージョンは best-effort 処理せず拒否。
        //    - signature と senderSigningPublicKey は「両方あり／両方なし」のみ許容
        //      （片方だけ present は構造改ざんの兆候）。
        //    - v2 以降で署名フィールドが欠落しているのは署名 strip 攻撃 → 拒否。
        guard (1...2).contains(file.version) else { throw ShareError.invalidFile }
        if (file.signature == nil) != (file.senderSigningPublicKey == nil) {
            throw ShareError.signatureInvalid
        }
        if file.version >= 2 && file.signature == nil {
            throw ShareError.signatureInvalid
        }

        // 1. エフェメラル公開鍵を復元
        guard let ephemeralKeyData = Data(base64Encoded: file.ephemeralPublicKey) else {
            throw ShareError.invalidFile
        }
        let ephemeralPublicKey = try P256.KeyAgreement.PublicKey(x963Representation: ephemeralKeyData)

        // 2. 署名検証（v2: senderSigningPublicKey + signature が両方存在する場合）
        //    併せて HKDF の sharedInfo を決定する（v2 は送信者署名公開鍵に束縛、v1 は空）。
        var isAuthenticated = false
        var senderFingerprint: String?
        var sharedInfo = Data() // v1: 空（後方互換）
        if let sigB64 = file.signature, let senderPubB64 = file.senderSigningPublicKey {
            guard
                let sigData = Data(base64Encoded: sigB64),
                let senderPubData = Data(base64Encoded: senderPubB64),
                let senderKey = try? P256.Signing.PublicKey(x963Representation: senderPubData)
            else {
                throw ShareError.signatureInvalid
            }
            let message = canonicalMessage(
                version: file.version,
                ephemeralPublicKeyB64: file.ephemeralPublicKey,
                encryptedDataB64: file.encryptedData,
                keyCount: file.keyCount,
                senderSigningPublicKeyB64: senderPubB64,
                createdAt: file.createdAt ?? ""
            )
            guard verify(message, signature: sigData, publicKey: senderKey) else {
                throw ShareError.signatureInvalid
            }
            isAuthenticated = true
            senderFingerprint = fingerprint(of: senderKey)
            sharedInfo = senderPubData // v2: 送信者署名公開鍵を束縛（attribution swap 防止）
        }

        // 3. ECDH で共有秘密を導出
        let sharedSecret = try recipientPrivateKey.sharedSecretFromKeyAgreement(with: ephemeralPublicKey)

        // 4. 対称鍵を導出（v2 は senderSigningPublicKey を sharedInfo に束縛）
        let symmetricKey = deriveSymmetricKey(from: sharedSecret, sharedInfo: sharedInfo)

        // 5. 復号
        guard let encryptedData = Data(base64Encoded: file.encryptedData) else {
            throw ShareError.invalidFile
        }
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        let plaintext = try AES.GCM.open(sealedBox, using: symmetricKey)

        // 6. キーデータをパース
        let entries = try JSONDecoder().decode([ShareFileFormat.KeyEntry].self, from: plaintext)

        let createdAtDate = file.createdAt.flatMap { iso8601.date(from: $0) }
        return DecryptedShare(
            entries: entries.map { ($0.envVarName, $0.value) },
            senderFingerprint: senderFingerprint,
            isAuthenticated: isAuthenticated,
            createdAt: createdAtDate
        )
    }

    /// .aikeychain ファイルを自分の秘密鍵で復号（v2 なら署名検証付き）
    static func decryptAndImport(from url: URL) throws -> DecryptedShare {
        guard let privateKey = loadPrivateKey() else {
            throw ShareError.noKeyPair
        }
        let json = try Data(contentsOf: url)
        let file = try JSONDecoder().decode(ShareFileFormat.EncryptedFile.self, from: json)
        return try decrypt(file: file, recipientPrivateKey: privateKey)
    }

    // MARK: - Private Key Storage

    private static func savePrivateKey(_ key: P256.KeyAgreement.PrivateKey) throws {
        try saveRawKey(key.rawRepresentation, service: privateKeyTag, account: "private_key")
    }

    private static func loadPrivateKey() -> P256.KeyAgreement.PrivateKey? {
        guard let data = loadRawKey(service: privateKeyTag, account: "private_key") else { return nil }
        return try? P256.KeyAgreement.PrivateKey(rawRepresentation: data)
    }

    /// 保存済みの署名アイデンティティを読み込む。
    ///
    /// 後方互換（#127）: 保存ブロブは
    ///   - Secure Enclave 鍵の `dataRepresentation`（不透明・可変長, 通常 32B 超）、または
    ///   - ソフトウェア鍵の `rawRepresentation`（厳密に 32B）
    /// のどちらか。SE を先に試し、失敗したら raw を試す。これにより #125 で作られた
    /// 既存のソフトウェア署名鍵はローテーションされず（＝フィンガープリント不変で）
    /// そのまま使い続けられる。SE init は 32B のソフトウェア raw を弾くため誤判定しない。
    private static func loadSigningIdentity() -> SigningIdentity? {
        guard let data = loadRawKey(service: signKeyTag, account: "signing_key") else { return nil }
        if SecureEnclave.isAvailable,
           let se = try? SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: data) {
            return .secureEnclave(se)
        }
        if let sw = try? P256.Signing.PrivateKey(rawRepresentation: data) {
            return .software(sw)
        }
        return nil
    }

    /// 署名ブロブを **非破壊** で追加する（`ensureSigningKey` のレース解消用）。
    /// 既存を消さず SecItemAdd のみ実行し、その OSStatus をそのまま返す。
    /// `errSecDuplicateItem` の場合は呼び出し側（resolveSigningIdentity）が既存を採用する。
    private static func addSigningBlob(_ blob: Data) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: signKeyTag,
            kSecAttrAccount as String: "signing_key",
            kSecValueData as String: blob,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        return SecItemAdd(query as CFDictionary, nil)
    }

    private static func saveRawKey(_ rawKey: Data, service: String, account: String) throws {
        // 既存を削除
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: rawKey,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw ShareError.keychainError(status)
        }
    }

    private static func loadRawKey(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return data
    }

    // MARK: - Errors

    enum ShareError: LocalizedError, Equatable {
        case noKeyPair
        case invalidPublicKey
        case invalidFile
        case encryptionFailed
        case signatureInvalid
        case keychainError(OSStatus)

        var errorDescription: String? {
            switch self {
            case .noKeyPair: "No key pair found. Generate one first."
            case .invalidPublicKey: "Invalid public key file."
            case .invalidFile: "Invalid or corrupted .aikeychain file."
            case .encryptionFailed: "Encryption failed."
            case .signatureInvalid:
                L10n.s(
                    ja: "署名の検証に失敗しました。ファイルが改ざんされたか、送信者の署名鍵と一致しません。",
                    en: "Signature verification failed. The file was tampered with, or does not match the sender's signing key."
                )
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

    /// 暗号化ファイル。v2 で送信者署名フィールドを追加したが、
    /// 追加分は Optional なので v1 JSON（署名フィールド無し）もそのままデコードできる。
    struct EncryptedFile: Codable {
        let version: Int
        let ephemeralPublicKey: String // base64 x963
        let encryptedData: String      // base64 AES-GCM sealed box
        let keyCount: Int
        // v2+ optional fields（v1 では欠落 → nil）
        let senderSigningPublicKey: String? // base64 x963 of P256.Signing.PublicKey
        let signature: String?              // base64 P256.Signing signature (raw)
        let createdAt: String?              // ISO8601

        init(
            version: Int,
            ephemeralPublicKey: String,
            encryptedData: String,
            keyCount: Int,
            senderSigningPublicKey: String? = nil,
            signature: String? = nil,
            createdAt: String? = nil
        ) {
            self.version = version
            self.ephemeralPublicKey = ephemeralPublicKey
            self.encryptedData = encryptedData
            self.keyCount = keyCount
            self.senderSigningPublicKey = senderSigningPublicKey
            self.signature = signature
            self.createdAt = createdAt
        }
    }

    struct KeyEntry: Codable {
        let envVarName: String
        let value: String
    }
}

// MARK: - Signing Abstraction (#127)

/// 正規メッセージへ署名できる主体の抽象。SE / ソフトウェアの差を暗号化・検証コードから隠す。
protocol MessageSigner {
    var signingPublicKey: P256.Signing.PublicKey { get }
    /// 正規メッセージへ署名し raw representation を返す。
    func signRaw(_ message: Data) throws -> Data
}

extension P256.Signing.PrivateKey: MessageSigner {
    var signingPublicKey: P256.Signing.PublicKey { publicKey }
    func signRaw(_ message: Data) throws -> Data {
        try signature(for: message).rawRepresentation
    }
}

/// 署名アイデンティティ。Secure Enclave 鍵（利用可能時）とソフトウェア鍵を統一的に扱う。
/// SE 鍵は秘密鍵素材が Enclave 内にあり `rawRepresentation` を持たないため、
/// 永続化には不透明な `dataRepresentation` を Keychain に保存する。
enum SigningIdentity: MessageSigner {
    case secureEnclave(SecureEnclave.P256.Signing.PrivateKey)
    case software(P256.Signing.PrivateKey)

    var signingPublicKey: P256.Signing.PublicKey {
        switch self {
        case .secureEnclave(let k): return k.publicKey
        case .software(let k): return k.publicKey
        }
    }

    func signRaw(_ message: Data) throws -> Data {
        switch self {
        case .secureEnclave(let k): return try k.signature(for: message).rawRepresentation
        case .software(let k): return try k.signature(for: message).rawRepresentation
        }
    }

    /// Secure Enclave に格納された鍵か（UI 表示・テスト用）。
    var isSecureEnclave: Bool {
        if case .secureEnclave = self { return true }
        return false
    }
}
