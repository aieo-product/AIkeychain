# AI KeyChain — env に API キーを晒さずに AI 開発する方法

## 記事メタ情報

- **想定媒体**: Zenn / Qiita / 個人ブログ
- **想定読者**: macOS で AI 開発をしている個人開発者・小規模チーム
- **キーワード**: API キー管理, macOS Keychain, プロキシ, Claude, OpenAI, セキュリティ, SwiftUI
- **トーン**: 技術ブログ（実体験ベース、課題→解決の流れ）
- **画像素材**: evidence/カスタムカテゴリ.png

---

## 導入 — 問題提起

AI 開発をしていると、こんな `.zshrc` になっていないだろうか。

```bash
export ANTHROPIC_API_KEY=sk-ant-api03-FQaun...
export OPENAI_API_KEY=sk-proj-...
export GITHUB_TOKEN=ghp_ENNotSwW...
```

`env` コマンドを叩けば全キーが平文で丸見え。
しかも **Claude Code や Cursor などの AI ツール自身がこの env を読み取れる** 状態。

実際に筆者の環境で `env` を実行した結果、11 個の API キー・トークンが全て平文で表示された。

### きっかけ — 障害発生

ある日、Claude Code が突然動かなくなった。

```
API Error: Unable to connect to API (ECONNREFUSED)
```

> localhost:9999 にプロキシ設定された状態で Claude が ECONNREFUSED エラーとなった

原因は `.zshrc` に `ANTHROPIC_BASE_URL=http://localhost:9999` が書き込まれていたこと。プロキシサーバーが起動していない状態で、全ての API リクエストが存在しないプロキシに向かっていた。

この障害をきっかけに「API キーの管理方法を根本的に見直す」ことにした。

---

## 課題の整理

### 1. env にキーが露出する

```bash
$ env | grep API_KEY
ANTHROPIC_API_KEY=sk-ant-api03-FQaun...  # 丸見え
```

AI ツールはプロセスの環境変数を読み取れる。つまり **Claude Code が自分自身の API キーを読める** 状態。

### 2. SSH 経由で Keychain 承認ができない

Tailscale SSH で Mac にリモート接続すると、`security find-generic-password` が GUI の承認ダイアログを出そうとして失敗する。SSH セッションではダイアログを表示する手段がない。

### 3. `.zshrc` への直接書き込みが危険

自動化ツールが `.zshrc` に設定を書き込むと、ツールが停止した時に全てのシェルセッションが壊れる。実際に 2 回この障害を経験した。

---

## 解決策 — AI KeyChain

macOS ネイティブのキー管理アプリを開発した。

**GitHub**: https://github.com/aieo-product/AIkeychain

### アーキテクチャ

2 つのモードを提供する。

#### Standard モード（安定・シンプル）

```
Terminal → export API_KEY=$(security ...) → API Server
```

従来の Keychain 参照方式。シンプルだが **env にキーが露出する**。

#### Proxy モード（高セキュリティ）

```
Terminal (env にキーなし)
  → HTTP リクエスト (認証ヘッダなし)
  → AI KeyChain Proxy (localhost:18121)
  → Keychain から API キーを読み取り
  → Authorization ヘッダを注入
  → API Server (api.anthropic.com)
```

- **env に API キーが一切露出しない**
- SSH 経由でも Keychain 承認ダイアログが不要
- プロキシは localhost のみで動作（外部からアクセス不可）

### なぜ Proxy 方式が有効か

| | Standard | Proxy |
|---|---|---|
| キーの保管 | macOS Keychain | macOS Keychain |
| キーの取り出し | `.zshrc` で export | プロキシがヘッダに注入 |
| **env にキーが見える？** | **見える** | **見えない** |
| アプリ常時起動が必要？ | いいえ | はい |

---

## 主要機能

### 4 ステップ env インポート

既存の env 変数を安全に Keychain に移行するウィザード。

1. **Get env** — ターミナルでコマンドを実行してコピー
2. **Scan** — 貼り付けた内容をパースし、リスクレベル別にレコメンド
   - AI API キー → Proxy 移行推奨
   - Bot トークン → 利用状況を確認
   - インフラ系 → Keychain 保存可能
3. **Preview** — 保存先と上書き有無を確認
4. **Import** — Keychain に保存 + `.zshrc` から export 行を自動削除

### プロキシのライフサイクル管理

最大の課題だった「プロキシが動いていないのに BASE_URL が残る」問題を構造的に解決。

```
プロキシ起動 → ~/.aikeychain_proxy を生成
プロキシ停止 → ~/.aikeychain_proxy を削除
PC 強制終了 → シェル起動時にポート応答チェック → ファイル自動削除
```

`.zshrc` には以下の 1 行だけ:
```bash
if [ -f ~/.aikeychain_proxy ]; then
  # ポートが応答するか確認してから source
  # 応答なし → ファイル自動削除
fi
```

### 暗号化キー転送

デバイス間でキーを安全に移行する機能。

- **暗号方式**: P-256 + ECDH + AES-256-GCM
- 移行先デバイスで鍵ペアを生成 → 公開鍵を移行元に渡す → 暗号化 → 復号 → Keychain に登録
- 秘密鍵は Keychain 内に保存（エクスポート不可）

### カスタムカテゴリ

プリセット 6 カテゴリ（AI API / AI Web / Code & Git / Cloud / Communication / Dev Tools）に加え、ユーザーが自由にカテゴリを追加・編集できる。

> **画像: evidence/カスタムカテゴリ.png**

---

## 技術スタック

| 項目 | 技術 |
|------|------|
| 言語 | Swift 5.9+ |
| UI | SwiftUI (macOS 14 Sonoma+) |
| 状態管理 | Observation framework (`@Observable`) |
| セキュリティ | Security.framework (Keychain Services) |
| プロキシ | Network.framework (`NWListener`) |
| 暗号化 | CryptoKit (P-256, AES-256-GCM, HKDF) |
| ビルド | Swift Package Manager |
| 配布 | Notarized DMG |

---

## 競合との比較

| 機能 | AI KeyChain | 1Password CLI | Doppler | LiteLLM Proxy |
|------|------------|---------------|---------|---------------|
| env にキーが見えない | **Proxy モード** | いいえ | いいえ | 設定ファイルに平文 |
| macOS ネイティブ GUI | **はい** | アプリはネイティブ | CLI のみ | Python |
| AI サービス特化 | **はい** | 汎用 | 汎用 | はい |
| クラウド不要 | **はい** | いいえ | いいえ | はい |
| 暗号化デバイス間転送 | **はい** | クラウド同期 | クラウド | いいえ |

**「macOS Keychain + ローカルプロキシで env にキーを露出させない」の組み合わせは既存ツールにない。**

---

## 障害から学んだこと

### `.zshrc` への自動書き込みは絶対にやってはいけない

2 回同じ障害を起こした。自動化ツールが `.zshrc` に BASE_URL を書き込み、ツール停止時に全セッションが壊れた。

**教訓**: ファイルベースのライフサイクル管理（起動時生成・停止時削除）+ シェルフックでのポート応答チェックが正解。

### GUI アプリはターミナルの env を見えない

macOS の GUI アプリは Finder 経由で起動するため、`.zshrc` で設定された環境変数を `ProcessInfo.processInfo.environment` で読み取れない。env スキャン機能を実装した際にこのことに気づき、Keychain 直接検索に切り替えた。

### API 利用規約を事前に確認する

キー共有機能を実装した後に各社の利用規約を調査したところ、個人 API キーの第三者共有は規約違反の可能性があることが判明。「Share Keys」→「Transfer Keys」に名称変更し、デバイス間移行用途に再定義した。

---

## 今後の予定

- Apple Developer Program 登録 → Notarization → Gatekeeper 警告なし配布
- Icon Composer でアイコン刷新
- プロキシリクエストログ・モニタリング機能
- GitHub Releases での配布

---

## まとめ

- `env` に API キーが丸見えの状態は、AI ツールが自身のキーを読めるリスクがある
- macOS Keychain + ローカルプロキシで、キーを env に露出させずに AI 開発できる
- この組み合わせを実現する既存ツールは見つからなかったため、自分で作った
- 障害を 2 回起こして「.zshrc への自動書き込みは危険」という知見を得た

**GitHub**: https://github.com/aieo-product/AIkeychain
**設計書**: https://aikeychain.pages.dev

---

## 補足: 記事化時の注意

- `env` コマンドの出力例はマスク処理すること
- GitHub リポジトリの URL は公開後に差し替え
