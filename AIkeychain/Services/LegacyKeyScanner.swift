import Foundation
import Security

/// v1.x で作られた「取り残しキー」を**読み取り専用・無音**で検出する (v2.0 #188)。
///
/// v2.0 は managed namespace (`com.aieo.aikeychain.managed`) のみを読む。旧 GUI
/// store (`com.aieo.aikeychain`) に作られたキー（GUI 作成・v1.8.1 までの `akc set`
/// はここに書いていた）は参照されなくなるため、初回起動で検出して「再登録して
/// ください」のツアーを出す判断材料にする。
///
/// **旧 GUI store（= AI KeyChain が確実に所有する service 名）のみを対象にする。**
/// manual スキーム（service=任意のキー名）は他アプリのアイテムと区別できず、
/// 新規インストールでの誤発火や取りこぼしを生むため対象外（#189 レビュー D-Q）。
///
/// **値は一切読まない**（`kSecReturnAttributes` のみ・`kSecReturnData` は使わない）
/// ので所有者に関係なくプロンプトは出ない。
enum LegacyKeyScanner {
    private static let managedService = SecurityCLIKeychainService.managedService  // com.aieo.aikeychain.managed
    private static let legacyGUIService = "com.aieo.aikeychain"

    /// managed に無い旧 GUI store キー名を昇順で返す（無ければ空）。実 Keychain を無音照会。
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

    /// 分類ロジック（純粋関数・テスト可能）: 旧 GUI store（service=com.aieo.aikeychain）
    /// の account で、managed に同名が無いものを返す。account が空/nil のレコードは
    /// キー名として扱えないので除外する（ツアーに空行を出さない）。
    static func unmigratedKeyNames(from records: [(service: String?, account: String?)]) -> [String] {
        var managed = Set<String>()
        var legacy = Set<String>()
        for (service, account) in records {
            guard let service else { continue }
            guard let account, !account.isEmpty else { continue }
            if service == managedService {
                managed.insert(account)
            } else if service == legacyGUIService {
                legacy.insert(account)
            }
        }
        return legacy.subtracting(managed).sorted()
    }
}
