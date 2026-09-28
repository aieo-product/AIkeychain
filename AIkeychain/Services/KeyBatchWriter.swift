import Foundation

/// `.env` インポート / キー共有受信の一括書込み（#215）。
///
/// 上書き判定に使う `exists()` は照会失敗時に `false` を返す（fail-open）ため、
/// 「新規」と表示したエントリを `-U` 付き `save` で書くと既存値を無確認に置き換え得る。
/// ユーザーが上書きと提示されたうえで承諾したエントリ（`overwriting`）だけを `save`（-U）で
/// 書き、それ以外は作成専用の `create`（-U なし）で書く。`create` が `duplicateItem` を
/// 返したら既存値を保護して「既存のためスキップ」として報告する。
enum KeyBatchWriter {
    struct Entry: Equatable {
        let account: String
        let value: String
    }

    struct Result: Equatable {
        var saved: [String] = []
        /// 既存と同名のため書き込まなかったキー（上書き未選択）。
        var skippedExisting: [String] = []
        /// 値形式が未対応（非 ASCII / 複数行 / 約 2,000 文字超）で保存できなかったキー。
        var unsupported: [String] = []
        /// その他の理由（keychain ロック等）で保存できなかったキー。
        var failed: [String] = []
    }

    /// 共有受信などで外部から来たエントリのうち、AI KeyChain 自身が管理する値
    /// （`keychain://` 参照・`<VALUE>` テンプレート・`AIKEYCHAIN_` 変数 / #219）を書込み対象から外す。
    static func partitionAppManaged(_ entries: [Entry]) -> (writable: [Entry], appManaged: [String]) {
        var writable: [Entry] = []
        var appManaged: [String] = []
        for entry in entries {
            if EnvParser.isAppManaged(key: entry.account, value: entry.value) {
                appManaged.append(entry.account)
            } else {
                writable.append(entry)
            }
        }
        return (writable, appManaged)
    }

    static func write(_ entries: [Entry],
                      overwriting: Set<String>,
                      keychain: KeychainServiceProtocol) -> Result {
        var result = Result()
        for entry in entries {
            do {
                if overwriting.contains(entry.account) {
                    try keychain.save(value: entry.value, for: entry.account)
                } else {
                    try keychain.create(value: entry.value, for: entry.account)
                }
                result.saved.append(entry.account)
            } catch KeychainError.duplicateItem {
                result.skippedExisting.append(entry.account)
            } catch KeychainError.invalidData {
                result.unsupported.append(entry.account)
            } catch {
                result.failed.append(entry.account)
            }
        }
        return result
    }
}
