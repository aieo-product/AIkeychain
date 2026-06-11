# CLI & MCP サーバー（npm パッケージ `aikeychain`）

GUI アプリなしで AI KeyChain のワークフローを使える CLI（`akc`）と、AI エージェント向け MCP サーバーを npm パッケージとして提供する。

## インストール

```bash
npm install -g aikeychain
# または都度実行
npx aikeychain <command>
```

要件: macOS（`security` コマンド使用）、Node.js 18+。

## CLI コマンド

| コマンド | 機能 |
|---|---|
| `akc run [--dry-run] -- <cmd>` | env の `keychain://` 参照を解決してコマンド実行（値は子プロセスのみに注入） |
| `akc list` | キー名一覧（値は一切表示しない） |
| `akc check <KEY>` | キーの存在・格納先（app / manual）確認 |
| `akc get <KEY>` | `keychain://<KEY>` 参照を出力（`--reveal` で生値） |
| `akc set <KEY>` | キー登録・更新（隠し入力 or stdin。値は `security -i` に stdin + hex で渡すため**どのプロセスの argv にも露出しない**。`-U` 相当の上書きで重複防止） |
| `akc delete <KEY>` | キー削除 |
| `akc doctor` | env / `~/.zshrc` の参照診断（`-a "$USER"` 落とし穴の検出含む） |
| `akc guide` | AI エージェント向け使い方ガイド表示 |
| `akc mcp` | MCP サーバー起動（stdio） |

### ルックアップ順序

bash 版 `scripts/akc` と互換（issue #91 対応済み）:

1. `service="com.aieo.aikeychain"` + `account=<KEY>`（GUI ストア）
2. `service=<KEY>` のみ・**account 非指定**（手動登録キー）

## MCP サーバー

### 登録

```bash
# Claude Code
claude mcp add aikeychain -- npx -y aikeychain mcp
```

```toml
# Codex CLI (~/.codex/config.toml)
[mcp_servers.aikeychain]
command = "npx"
args = ["-y", "aikeychain", "mcp"]
```

### 提供ツール

| ツール | 内容 | 生値の露出 |
|---|---|---|
| `usage_guide` | 正しいシークレット運用ガイド | なし |
| `list_keys` | キー名と格納先の一覧 | なし |
| `check_key` | キーの存在確認 | なし |
| `get_secret_reference` | `keychain://` 参照と利用例 | なし |
| `set_secret` | キーの保存（上書き） | 入力のみ（ユーザー自身の `akc set` を推奨） |
| `delete_secret` | キーの削除（`confirm: true` 必須） | なし |
| `doctor` | 設定診断（マスク表示） | なし |

### セキュリティ設計

**生値を返すツールは存在しない。** エージェントは `get_secret_reference` で参照を取得し、実際のワークロードは `akc run` 経由で実行する。これによりシークレット値はモデルのコンテキストに一切載らない。

```
AI エージェント                akc run                    子プロセス
  │ get_secret_reference         │                            │
  │ → keychain://GITHUB_TOKEN    │                            │
  │ Bash: akc run -- <cmd> ────▶ │── Keychain 解決 ──▶        │
  │   (モデルは値を見ない)         │── 値を env 注入 ─────────▶ │
```
