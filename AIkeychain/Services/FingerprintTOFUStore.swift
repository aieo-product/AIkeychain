import Foundation

/// 送信者フィンガープリントの TOFU（Trust On First Use）ピン留めストア（#126）。
///
/// 一度ユーザーが帯域外照合して確認した送信者のフィンガープリントを永続化し、
/// 次回以降の受信で「既知の送信者」として扱えるようにする。これにより
/// 毎回のフル照合負担を下げつつ、初見の（＝ストアに無い）フィンガープリントに対しては
/// 引き続きフル照合を要求できる。
///
/// 各フィンガープリントは 1 送信者に一意対応するため「フィンガープリントの変化」は
/// 概念として存在しない（別のフィンガープリント＝別の送信者）。したがって
/// ストアが空でない状態で新しいフィンガープリントが来た場合は、
/// それは「新しい送信者」であり、引き続き帯域外照合が必須となる。
///
/// 保存形式は UserDefaults の `[fingerprint: firstSeen(参照時刻からの秒)]` 辞書。
/// テスト分離のため `UserDefaults` を注入できる。
///
/// ⚠️ 残存リスク（改ざん面）: このピンは **署名なしの user-writable な UserDefaults** に
/// 保存される。同一ユーザー権限で動くプロセスは、この辞書へ直接書き込むことで
/// 任意のフィンガープリントを「既知の送信者」として事前 seed（詐称）できる。
/// これは緩和済み（ROOT ではなく UX 補助）であり、インポート時の帯域外照合チェックは
/// TOFU 状態に関わらず**常に必須**であるため、seed 単独では検証ゲートを回避できない。
/// より強い保証が必要なら将来的に MAC 化（例: Keychain 由来の鍵で HMAC）を検討する
/// （本 PR ではスコープ外）。
struct FingerprintTOFUStore {
    /// 送信者の信頼状態。
    enum SenderTrust: Equatable {
        /// ストアに無い初見のフィンガープリント。フル照合が必要。
        case firstSeen
        /// 過去に確認済み（ピン留め済み）のフィンガープリント。
        case known(since: Date)

        var isKnown: Bool {
            if case .known = self { return true }
            return false
        }
    }

    private static let storeKey = "com.aieo.aikeychain.tofu.fingerprints"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 現在ピン留めされている `[fingerprint: firstSeenDate]`。
    private func pinned() -> [String: Date] {
        guard let raw = defaults.dictionary(forKey: Self.storeKey) as? [String: Double] else {
            return [:]
        }
        return raw.mapValues { Date(timeIntervalSinceReferenceDate: $0) }
    }

    private func write(_ dict: [String: Date]) {
        let raw = dict.mapValues { $0.timeIntervalSinceReferenceDate }
        defaults.set(raw, forKey: Self.storeKey)
    }

    /// ストアが空か（＝これまで誰も確認していない）。
    var isEmpty: Bool { pinned().isEmpty }

    /// 指定フィンガープリントが確認済みか。
    func isKnown(_ fingerprint: String) -> Bool {
        pinned()[fingerprint] != nil
    }

    /// 初回確認日時（未確認なら nil）。
    func firstSeen(_ fingerprint: String) -> Date? {
        pinned()[fingerprint]
    }

    /// フィンガープリントを信頼状態に分類する。
    func classify(_ fingerprint: String) -> SenderTrust {
        if let since = pinned()[fingerprint] {
            return .known(since: since)
        }
        return .firstSeen
    }

    /// ユーザーが認証済みインポートを確定した際にフィンガープリントをピン留めする。
    /// 既に存在する場合は firstSeen 日時を保持する（上書きしない）。
    func confirm(_ fingerprint: String, at date: Date = Date()) {
        var dict = pinned()
        if dict[fingerprint] == nil {
            dict[fingerprint] = date
            write(dict)
        }
    }

    /// テスト用: ストアを全消去する。
    func reset() {
        defaults.removeObject(forKey: Self.storeKey)
    }
}
