<p align="center">
  <img src="AIkeychain/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" height="128" alt="AI KeyChain" />
</p>

<h1 align="center">AI KeyChain</h1>

<p align="center">
  <strong>Secure API key manager for AI developers on macOS</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014+-blue?style=flat-square" />
  <img src="https://img.shields.io/badge/Swift-5.9+-orange?style=flat-square&logo=swift" />
  <img src="https://img.shields.io/badge/SwiftUI-Native-purple?style=flat-square" />
  <img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" />
</p>

<p align="center">
  <a href="#installation">Installation</a> |
  <a href="#features">Features</a> |
  <a href="#how-it-works">How It Works</a> |
  <a href="#supported-services">Supported Services</a> |
  <a href="https://aieo-product.github.io/AIkeychain/">Docs</a> |
  <a href="#日本語">日本語</a>
</p>

---

## Why AI KeyChain?

AI developers juggle dozens of API keys. Most store them in `.env` or `.zshrc` in plaintext — visible via `env` command, leaked in logs, and exposed to every process.

**AI KeyChain** stores your keys in macOS Keychain (encrypted, hardware-backed) and offers three modes to use them:

| | Standard | Secret Reference | Proxy |
|---|---|---|---|
| Storage | macOS Keychain | macOS Keychain | macOS Keychain |
| How keys reach tools | `export` in `.zshrc` | `keychain://` reference + `akc run` | Local proxy injects auth headers |
| Keys in `env` (parent) | Key values | Reference path only | No keys |
| Keys in child process memory | Yes | Yes (injected by `akc run`) | **No** |
| Process-dump leakage | Risk | Risk | **Safe** |
| Requires app always-on | No | No | Yes |
| Direct SDK exec | OK | Needs `akc run` | OK |
| Security level | ★☆☆ | ★★☆ | ★★★ |
| Best for | Simplicity | 1Password-style workflow (`op://` equivalent) | Security-critical environments |

## Installation

### Download DMG

Download the latest release from [Releases](https://github.com/aieo-product/AIkeychain/releases).

1. **Verify the download's checksum** — see [Verify your download](#verify-your-download) below.
2. Open the DMG and drag **AI KeyChain.app** to **Applications**
3. Launch the app — no extra steps needed.

> **Note:** Since v1.8.0, releases are signed with a Developer ID certificate (Team `34J49FY7U7`), notarized by Apple, and stapled, so Gatekeeper accepts the app without any manual `xattr` workaround. If macOS warns that the app is damaged or from an unidentified developer, do **not** bypass Gatekeeper — verify the asset with `spctl --assess --type open --context context:primary-signature -vv AIKeyChain-vX.Y.Z.dmg` (expect `accepted / Notarized Developer ID`) and re-download the latest release.
>
> **Upgrading from v1.x:** v2.0 stores keys in a new single namespace and no longer reads keys registered by older versions (they are not deleted). On first launch the app shows an upgrade tour listing the keys to re-register — re-add each with the app's **+** or `akc set <KEY>`.

### Verify your download

Each release publishes a `.sha256` checksum file alongside the DMG (e.g. `AIKeyChain-vX.Y.Z.dmg.sha256`). Download both files from the same [release](https://github.com/aieo-product/AIkeychain/releases) and verify before opening:

```bash
shasum -a 256 -c "AIKeyChain-vX.Y.Z.dmg.sha256"
```

Or compare manually:

```bash
shasum -a 256 "AIKeyChain-vX.Y.Z.dmg"
# compare the printed hash against the value in AIKeyChain-vX.Y.Z.dmg.sha256 from the same release
```

> **Note:** The `.sha256` file is hosted in the same GitHub Release as the DMG, so this is a **download-integrity check only** — it catches corrupted downloads or a tampered mirror, but an attacker who can replace the release asset could also replace the checksum. Authenticity comes from the Developer ID signature + Apple notarization (v1.8.0+), which Gatekeeper verifies automatically — and which you can check explicitly with `spctl --assess --type open --context context:primary-signature -vv <dmg>`. An asset that fails that check is not an official build, whatever its checksum says.

### Build from Source

```bash
git clone https://github.com/aieo-product/AIkeychain.git
cd AIkeychain
swift build -c release
```

## Features

- **macOS Keychain integration** — Keys are encrypted at rest using the Secure Enclave
- **Three management modes** — Choose Standard (simple), Secret Reference (1Password-style), or Proxy (env-safe) at first launch
- **Local auth proxy** — Intercepts API requests and injects credentials from Keychain
- **Guided onboarding** — Step-by-step setup with animated mode comparison
- **Menu bar resident** — Proxy status always visible, one-click control
- **4-step env import wizard** — Scan, recommend, preview, and import keys from env
- **Encrypted key transfer** — P-256 + AES-256-GCM for secure device-to-device migration
- **Custom categories** — Create your own categories with icons and colors
- **Shell cleanup tool** — Find and remove hardcoded keys from your `.zshrc`
- **Recovery guide** — Built-in troubleshooting for proxy mode issues
- **Port configuration** — Choose your proxy port (default: 18121)

> **Note:** The proxy binds to `localhost` (127.0.0.1) only. API keys never leave the Keychain into environment variables in Proxy mode. The key transfer feature is designed for migrating keys between your own devices. Sharing personal API keys with third parties may violate service provider terms.

## How It Works

### Standard Mode
```
Terminal                                                          API Server
  │  export API_KEY=$(/usr/bin/security find-generic-password \   │
  │    -s "com.aieo.aikeychain.managed" -a "API_KEY" -w)           │
  │────────────────────── API key in request ────────────────────▶│
```

> The generated `.zshrc` line pins **both** the service (`com.aieo.aikeychain.managed`)
> and the account (the key name), matching how every key is stored — this avoids the
> `-a "$USER"` pitfall of stale or duplicate `acct` values.

> **Common AI-agent mistake:** looking up a stored key with the bare
> `/usr/bin/security find-generic-password -s "API_KEY" -w` (service name only, no `-a`)
> returns "could not be found" (exit 44). That is **not** proof the key is
> unregistered — it just means the wrong lookup form was used. Use `akc get
> API_KEY` / `akc check API_KEY` (see [CLI & MCP
> Server](#cli--mcp-server-npm) below), or the two-attribute `security` form
> shown above, instead of concluding the key is missing.

### Proxy Mode
```
Terminal               AI KeyChain Proxy          API Server
  │  (no key in env)        │                         │
  │── request (no auth) ──▶ │── Keychain read ──▶     │
  │                         │── inject auth header ──▶│
  │◀── response ──────────  │◀── response ──────────  │
```

The proxy runs on `localhost` only. Keys never leave the Keychain into environment variables.

## CLI & MCP Server (npm)

The [`aikeychain`](cli/) npm package provides a standalone CLI (`akc`) and an MCP server — no GUI app required:

```bash
npm install -g aikeychain    # or: npx aikeychain
akc init                     # set up AI-agent discovery machine-wide (Claude + Codex)

# Secret Reference workflow
export OPENAI_API_KEY=keychain://OPENAI_API_KEY
akc run -- claude            # real value injected into the child process only
# Headless contract: every key is in the managed namespace and resolves silently
# — no prompts, no hangs. (v2.0 dropped the v1.x GUI store / manual scheme; if you
# upgraded, re-register your keys with `akc set <KEY>`.)

akc list                     # key names (never prints values)
akc set GITHUB_TOKEN         # hidden prompt, overwrites in place
akc doctor                   # diagnose env + ~/.zshrc references
```

Let AI agents (Claude Code, Codex, ...) use AI KeyChain correctly — run **`akc init`** once and every future session on the machine discovers it via the MCP tools and the instructions block written into `~/.claude/CLAUDE.md` / `~/.codex/AGENTS.md`. To register the Claude MCP server manually instead:

```bash
claude mcp add --scope user aikeychain -- akc mcp
```

The MCP tools (`usage_guide`, `list_keys`, `check_key`, `get_secret_reference`, `set_secret`, `delete_secret`, `doctor`) **never return raw secret values to the model** — agents get `keychain://` references and run workloads through `akc run`. See [cli/README.md](cli/README.md) for details.

## Supported Services

| Category | Services |
|----------|----------|
| **AI** | Anthropic (Claude) / OpenAI / xAI (Grok) / Higgsfield |
| **Code & Git** | GitHub / GitLab |
| **Cloud** | Cloudflare / Tailscale |
| **Communication** | Discord / Slack |
| **Dev Tools** | Qiita |

## Tech Stack

- **Language**: Swift 5.9+
- **UI**: SwiftUI (macOS 14 Sonoma+)
- **State**: Observation framework (`@Observable`)
- **Security**: Security.framework (Keychain Services API)
- **Proxy**: Network.framework (`NWListener`)
- **Build**: Swift Package Manager

## Documentation

Design docs are available at **[aieo-product.github.io/AIkeychain](https://aieo-product.github.io/AIkeychain/)**

- [Architecture](https://aieo-product.github.io/AIkeychain//design/architecture)
- [Data Model](https://aieo-product.github.io/AIkeychain//design/data-model)
- [Security](https://aieo-product.github.io/AIkeychain//design/security)
- [Test Results](https://aieo-product.github.io/AIkeychain//test/)

## License

MIT License. See [LICENSE](LICENSE) for details.

## Disclaimer

- API keys are stored encrypted in macOS Keychain (backed by Secure Enclave).
- In Proxy mode, keys are designed to never be exposed as environment variables.

However, this software is provided **"AS IS"**.
The author assumes no responsibility for any damages resulting from the use of this application, including but not limited to API key leakage, unexpected charges, or data loss.

**Use entirely at your own risk.**

### Trademarks

This is an independent project and is **not affiliated with, endorsed by, or sponsored by Apple Inc.** "Apple", "macOS", and "Keychain" are trademarks of Apple Inc., used here for descriptive and identification purposes only.

---

<a id="日本語"></a>

## 日本語

<p align="center">
  <strong>AI 開発者のための macOS ネイティブ鍵管理アプリ</strong>
</p>

### AI KeyChain とは？

AI 開発では多数の API キーを扱います。多くの開発者はこれらを `.env` や `.zshrc` に平文で保存しており、`env` コマンドで丸見え、ログに漏洩、全プロセスからアクセス可能な状態です。

**AI KeyChain** は API キーを macOS Keychain（暗号化・ハードウェア保護）に保管し、3つのモードで利用できます。

### モード比較

| | Standard | Secret Reference | Proxy |
|---|---|---|---|
| 保管場所 | macOS Keychain | macOS Keychain | macOS Keychain |
| キーの取り出し方 | `.zshrc` で `export` | `keychain://` 参照 + `akc run` | ローカルプロキシが認証ヘッダを注入 |
| 親プロセスの `env` | キー値あり | パスのみ | キーなし |
| 子プロセスのメモリ | キーあり | キーあり（`akc run` で注入） | **キーなし** |
| プロセスダンプ漏洩 | リスクあり | リスクあり | **リスクなし** |
| アプリ常時起動 | 不要 | 不要 | 必要 |
| SDK 直接実行 | 可能 | `akc run` 必要 | 可能 |
| セキュリティレベル | ★☆☆ | ★★☆ | ★★★ |
| 向いている用途 | シンプルに使いたい | 1Password 方式（`op://` 同等） | セキュリティ重視の環境 |

> **AI エージェントによくある誤り:** 保存したキーを `/usr/bin/security
> find-generic-password -s "API_KEY" -w`（サービス名のみ、`-a` なし）で引くと
> "could not be found"（exit 44）になりますが、これは**「未登録」の証拠ではありません**。
> managed namespace のキーには誤ったルックアップ方法を使っているだけです。
> `akc get API_KEY` / `akc check API_KEY`（後述の「CLI & MCP サーバー」）か、
> `/usr/bin/security find-generic-password -s "com.aieo.aikeychain.managed" -a "API_KEY" -w`
> （service + account の両方を指定する形）を使ってください。

### インストール

#### DMG ダウンロード

[Releases](https://github.com/aieo-product/AIkeychain/releases) から最新版をダウンロードしてください。

1. **ダウンロードのチェックサムを検証してください**（下記「ダウンロードの検証」参照）。
2. DMG を開き、**AI KeyChain.app** を **Applications** フォルダにドラッグ
3. そのまま起動できます — 追加の手順は不要です。

> **注意:** v1.8.0 以降のリリースは Developer ID 証明書（Team `34J49FY7U7`）で署名し、Apple の公証（Notarization）+ staple 済みのため、Gatekeeper の警告なしでそのまま起動できます。「壊れているため開けません」「開発元を確認できません」と表示された場合は **Gatekeeper を回避せず**、`spctl --assess --type open --context context:primary-signature -vv AIKeyChain-vX.Y.Z.dmg` で資産を検証（`accepted / Notarized Developer ID` が正）した上で最新リリースを取り直してください。
>
> **v1.7.x 以前からのアップデート:** 署名が ad-hoc から Developer ID に変わったため、初回アクセス時に保存済みキーごとの Keychain 承認ダイアログが一度だけ表示されます。**「常に許可」**を選べば、以後のアップデートでは再承認は発生しません。

#### ダウンロードの検証

各リリースには DMG と同時に `.sha256` チェックサムファイルが公開されます（例: `AIKeyChain-vX.Y.Z.dmg.sha256`）。同じ[リリース](https://github.com/aieo-product/AIkeychain/releases)から両方をダウンロードし、開く前に検証してください:

```bash
shasum -a 256 -c "AIKeyChain-vX.Y.Z.dmg.sha256"
```

または手動で比較:

```bash
shasum -a 256 "AIKeyChain-vX.Y.Z.dmg"
# 出力されたハッシュ値を同リリースの AIKeyChain-vX.Y.Z.dmg.sha256 の値と比較する
```

> **注意:** `.sha256` ファイルは DMG と同じ GitHub Release に置かれているため、これは**ダウンロードの完全性チェック**です（破損やミラー改ざんは検出できますが、リリース資産を差し替えられる攻撃者はチェックサムも差し替えられます）。真正性は v1.8.0 以降の Developer ID 署名 + Apple 公証が担い、Gatekeeper が自動検証します。`spctl --assess --type open --context context:primary-signature -vv <dmg>` で明示的に確認でき、この検証を通らない資産はチェックサムが合っていても公式ビルドではありません。

#### ソースからビルド

```bash
git clone https://github.com/aieo-product/AIkeychain.git
cd AIkeychain
swift build -c release
```

### 主な機能

- **macOS Keychain 統合** — Secure Enclave によるハードウェアレベルの暗号化
- **3つの管理モード** — 初回起動時に Standard（シンプル）/ Secret Reference（1Password 方式）/ Proxy（高セキュリティ）から選択
- **ローカル認証プロキシ** — API リクエストを中継し、Keychain からキーを読み取ってヘッダに注入
- **ガイド付きオンボーディング** — アニメーション付きのモード比較で直感的にセットアップ
- **メニューバー常駐** — プロキシ状態を常に確認、ワンクリックで制御
- **4ステップ env インポート** — env のスキャン・レコメンド・プレビュー・一括登録
- **暗号化キー転送** — P-256 + AES-256-GCM によるデバイス間の安全な移行
- **カスタムカテゴリ** — アイコン・カラーを選んで独自カテゴリを作成
- **Shell Cleanup** — `.zshrc` に残っているハードコードされたキーを調査・削除するガイド
- **復旧ガイド** — Proxy モードで問題が起きた場合の復旧手順を内蔵
- **ポート設定** — プロキシポートを自由に変更可能（デフォルト: 18121）

> **注意:** プロキシは `localhost` (127.0.0.1) のみで動作します。Proxy モードでは API キーが環境変数に一切露出しません。キー転送機能はデバイス間の移行を想定しています。個人 API キーの第三者への共有は各サービスの利用規約に違反する可能性があります。

### Proxy モードの仕組み

```
Terminal               AI KeyChain Proxy          API Server
  │  (env にキーなし)       │                         │
  │── リクエスト(認証なし)─▶│── Keychain 読み取り ──▶  │
  │                         │── 認証ヘッダ注入 ──────▶│
  │◀── レスポンス ─────────  │◀── レスポンス ─────────  │
```

プロキシは `localhost` のみで動作。キーが環境変数に露出することはありません。

### CLI & MCP サーバー（npm）

GUI アプリなしでも使える CLI（`akc`）と MCP サーバーを npm パッケージ [`aikeychain`](cli/) として提供しています。

```bash
npm install -g aikeychain    # または npx aikeychain

export OPENAI_API_KEY=keychain://OPENAI_API_KEY
akc run -- claude            # 実際の値は子プロセスにのみ注入

akc list                     # キー名一覧（値は表示しない）
akc set GITHUB_TOKEN         # 隠し入力で登録（重複エントリを作らず上書き）
akc doctor                   # env / ~/.zshrc の参照を診断
```

AI エージェント（Claude Code / Codex 等）から正しく使わせるには MCP サーバーを登録します：

```bash
claude mcp add aikeychain -- npx -y aikeychain mcp
```

MCP ツールは**シークレットの生値をモデルに返さない**設計です（`keychain://` 参照 + `akc run` 注入で完結）。詳細は [cli/README.md](cli/README.md) を参照。

### 対応サービス

| カテゴリ | サービス |
|---------|---------|
| **AI** | Anthropic (Claude) / OpenAI / xAI (Grok) / Higgsfield |
| **コード & Git** | GitHub / GitLab |
| **クラウド** | Cloudflare / Tailscale |
| **コミュニケーション** | Discord / Slack |
| **開発ツール** | Qiita |

### 設計書

設計書は VitePress で公開しています: **[aieo-product.github.io/AIkeychain](https://aieo-product.github.io/AIkeychain/)**

### ライセンス

MIT License

### 免責事項

- APIキーはmacOS Keychain（Secure Enclave使用）に暗号化されて保存されます。
- Proxyモードではキーが環境変数に一切露出しないよう設計しています。

しかしながら、本ソフトウェアは**「AS IS（現状のまま）」**で提供されます。
作者は本アプリの使用によって生じたいかなる損害（APIキー漏洩、請求発生、データ損失など）についても一切の責任を負いません。

**すべて自己責任**でご利用ください。

### 商標について

本プロジェクトは独立したプロジェクトであり、**Apple Inc. とは一切提携しておらず、Apple による承認・後援も受けていません**。「Apple」「macOS」「Keychain」は Apple Inc. の商標であり、本書では説明・識別の目的でのみ使用しています。
