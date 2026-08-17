import Foundation
import Security

/// v1.x で作られた「取り残しキー」を**読み取り専用・無音**で検出する (v2.0 #188)。
///
/// v2.0 は managed namespace のみを読む。アップグレードしたユーザーの旧キー
/// （旧 GUI store `com.aieo.aikeychain` の account / manual スキームの
/// service=<KEY>）は参照されなくなるため、初回起動でこれらを検出して
/// 「再登録してください」のツアーを出す判断材料にする。
///
/// **値は一切読まない**（`kSecReturnAttributes` のみ・`kSecReturnData` は使わない）
/// ので所有者に関係なくプロンプトは出ない。CLI の `findUnmigratedKeys`
/// （cli/src/keychain.js）と同一の判定規則。
enum LegacyKeyScanner {
    private static let managedService = SecurityCLIKeychainService.managedService  // com.aieo.aikeychain.managed
    private static let legacyGUIService = "com.aieo.aikeychain"
    // KeyShareService のアプリ内部鍵（移行/検出の対象外）
    private static let reservedServices: Set<String> = [
        "com.aieo.aikeychain.sharekey", "com.aieo.aikeychain.signkey",
    ]
    // manual スキーム判定: 大文字スネークケース限定（CLI の MANUAL_NAME_PATTERN と同一）。
    // 緩いと iCloud / AirPort 等のシステムアイテムを誤検出する。
    private static let manualNamePattern = #"^[A-Z][A-Z0-9_]*$"#

    /// managed に無い旧 v1 キー名を昇順で返す（無ければ空）。実 Keychain を無音照会。
    static func unmigratedKeyNames() -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,  // 属性のみ = 無音
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else {
            return []
        }
        let records = items.map {
            (service: $0[kSecAttrService as String] as? String,
             account: $0[kSecAttrAccount as String] as? String)
        }
        return unmigratedKeyNames(from: records)
    }

    /// 分類ロジック（純粋関数・テスト可能）。CLI の `findUnmigratedKeys` と同一規則:
    /// 旧 GUI store の account / manual スキームの service 名で、managed に無いもの。
    static func unmigratedKeyNames(from records: [(service: String?, account: String?)]) -> [String] {
        var managed = Set<String>()
        var legacy = Set<String>()
        for (service, account) in records {
            guard let service else { continue }
            if service == managedService {
                if let account { managed.insert(account) }
            } else if service == legacyGUIService {
                if let account { legacy.insert(account) }
            } else if !reservedServices.contains(service),
                      service.range(of: manualNamePattern, options: .regularExpression) != nil {
                legacy.insert(service)  // manual スキームは service 名がキー名
            }
        }
        return legacy.subtracting(managed).sorted()
    }
}
