# リリース履歴

リリース済みバージョンの主な変更点。詳細は [`CHANGELOG.md`](https://github.com/aieo-product/AIkeychain/blob/main/CHANGELOG.md) を参照。

## v1.6.0 — Secret Reference モード対応

### 追加
- **Secret Reference モード** — `keychain://KEY_NAME` 参照を `akc run` が実行時に解決し、親 env にキー値を露出させない
- **`akc` CLI** (`scripts/akc`) — `--dry-run` で対象キーをマスク表示
- **Activity 画面** — プロキシ通過リクエストのリアルタイム表示 (時刻 / ホスト / メソッド / パス / ステータス / レイテンシ)
- **`ProxyLogStore`** — メモリ上のみで保持されるリクエストログ (ディスク永続化なし)
- **セッショントークン認証** — `X-AIKeyChain-Token` ヘッダで localhost 同居プロセスからの不正利用を防止
- **アプリ表示言語切替 (ja / en)** — オンボーディング初回ステップで選択、`L10n` テーブル経由で全画面を切替
- **オンボーディングに言語選択ステップを追加** — 6 ステップ構成

### 変更
- ExportView に **Secret Reference 形式** を追加 (`.zshrc / Secret Reference / .env` の 3 形式)
- ModeSelectView を 3 モード (Standard / Secret Reference / Proxy) のカード選択に再構成

## v1.1.0 — モード選択と復旧 UX

### 追加
- Standard / Proxy モード選択
- Proxy モード同意画面
- Recovery Guide / Shell Cleanup ツール
- プロキシ設定ファイルのライフサイクル管理 (`~/.aikeychain_proxy`)
- 強制終了時のフォールバック (`.zshrc` フックでヘルスチェック → 古い設定を自動削除)
- ポート設定 UI、ポート永続化
- アニメーション付きオンボーディング モード比較
- DMG インストーラ (背景画像つき)
- アドホックコード署名

### 変更
- デフォルトポート 9999 → 18121
- `.zshrc` への自動書き込み廃止 (ライフサイクルファイル経由に統一)

### 修正
- プロキシ未稼働時に残った `ANTHROPIC_BASE_URL` 起因の ECONNREFUSED

## v1.0.0 — 初回リリース

### 追加
- macOS Keychain 統合 (Security.framework CRUD)
- ローカル認証プロキシ (`NWListener`)
- 主要 AI / Git / Cloud / Communication / Dev Tools サービス対応
- メニューバー常駐
- 5 ステップのオンボーディング
- キーエディタ (プレフィックス検証)
- カテゴリサイドバー
- `.zshrc` / `.env` エクスポート
- ヘルプ画面
- Launch at Login (`SMAppService`)

## v0.1.0 — プロジェクトスキャフォールド

### 追加
- Swift Package Manager + XcodeGen 構成
- VitePress 設計ドキュメントサイト
- Cloudflare Pages デプロイ
