# Changelog

All notable changes to AI KeyChain are documented in this file.

## [2.0.0] - 2026-08-17

完全リニューアル。単一の managed namespace (`com.aieo.aikeychain.managed`) を唯一の保管場所に絞り、v1.x の後方互換（旧 GUI store / manual スキーム）を全撤去した。

### ⚠️ 破壊的変更（BREAKING）
- **v1.x で登録したキーは読まれなくなります。** GUI アプリまたは `akc set <KEY>` で**キーを登録し直してください**。旧キーは削除されず macOS Keychain に残りますが、AI KeyChain / `akc` からは参照しません。
- `akc set --manual` / MCP の `manual` フィールドを廃止（すべて managed namespace に書き込む）。

### Added
- **アップグレード・ツアー** — v1.x から更新したユーザーの初回起動時、旧方式（旧 GUI store / manual スキーム）にしか無いキーを**読み取り専用・無音で検出**し、「再登録が必要なキー一覧」と v2.0 の使い方を案内するツアーを表示。新規インストール（旧キー無し）は従来の onboarding のまま。検出は `dump-keychain` 相当の属性照会のみで値は読まない（プロンプトゼロ）(#188)

### Changed
- **単一 namespace 化** — resolver を 3 段ルックアップ（managed → 旧 GUI → manual）から **managed 単一**に簡素化。`security` 所有なのでヘッドレス読取はプロンプト/ハングしない。fail-closed 契約（exit 44 のみ not-found、それ以外は権威的失敗）は維持 (#188)
- CLI（`cli/`）・bash 版（`scripts/akc`）・GUI（Swift）すべてを managed 単一に統一。GUI のキー発見・`.zshrc` エクスポート・削除も managed のみを対象に
- **値の長さ上限を実効値に修正**: `security -i` の 1 行上限（4096 バイト fgets バッファ = 4094 文字 + 改行）により、保存できる値は `floor((4094 − 66 − キー名長) / 2) ≒ 2,000 文字`（従来の 8192 宣言は到達不能だった）。上限超過は `security` を呼ぶ前に明示的なエラーで拒否し、失敗時のエラー文言から hex 化した値の断片を無条件に除去（CLI / GUI / MCP `set_secret` 共通）。hex 方式は `security -i` への注入防止として維持し、より長い値は対象外とする (#191)

### Removed
- 旧 GUI store / manual スキームの読み取り fallback・書き込み・削除掃除
- `akc doctor` の「未移行キー検出」/ 曖昧重複検出（legacy 前提の診断）
- `findUnmigratedKeys` / `findAmbiguousDuplicates` / `MigrationRequiredError`（CLI）、`manualServices()` / `StorageScheme` / legacy 値読取（Swift）
- これに伴い legacy 由来の既知バグ（#186 manual 重複削除・#187 doctor の managed 行誤解析）は経路ごと解消

### 注記
- 移行アシスタント（旧 #172 C5）は、旧バージョンの利用実績がほぼ無いこと（DL 実測）を踏まえ**作らない判断**とした。互換の複雑さ（secret oracle・移行の crash-safe 化など）を丸ごと回避している。

## [1.8.1] - 2026-08-13

### Fixed
- **GUI 値編集による CLI 管理キーの毒化を防止（データ整合性）** — `akc set` または手動 `security add-generic-password` で登録した `/usr/bin/security` 所有キーの値を GUI で編集すると、in-process `SecItemUpdate` が**無音で成功しつつ所有権を破壊し、以後 `akc run` がヘッドレスでそのキーを読めなくなる**（プロンプト待ちでハング）実機確認済みの不具合を修正。GUI は該当キーの in-process 上書きをやめ、`SecItemDelete` を「プロンプトを出さない所有権プローブ」に用いて、CLI 管理キーは**値を変更せず fail-closed** し「`akc set <KEY>` で更新してください」と案内する。GUI 所有キーは従来どおり編集可能 (#177)
- **.env インポート / キー共有インポートでの取りこぼしを可視化** — 上記により CLI 管理キーはインポート時に上書きされないため、「N 件は akc CLI 管理のため未更新（`akc set` で更新）」を結果画面に明示。古い/失効済みの値がサイレントに残る問題を解消 (#177)

## [1.8.0] - 2026-08-12

### Added
- **Developer ID 署名 + Apple 公証（Notarization）による正式配布** — 配布 DMG と .app を Developer ID Application 証明書（Team `34J49FY7U7`）+ Hardened Runtime（`--options runtime --timestamp`）で署名し、Apple 公証 + staple 済みで配布。Gatekeeper 警告なしでそのままインストール・起動できる。Hardened Runtime により `DYLD_INSERT_LIBRARIES` 注入やデバッガアタッチからシークレット保持プロセスを防御 (#34, #114)
- **`scripts/build-release.sh`** — ビルド → .app バンドル → Developer ID 署名 → .app 公証/staple → DMG 作成 → DMG 署名/公証/staple → `spctl` 検証 → SHA-256 生成までを全自動化するリリーススクリプト

### Changed
- **README のインストール手順** — 公証済み配布に伴い、`xattr -dr com.apple.quarantine` による Gatekeeper 回避手順を撤廃（EN/JA）。チェックサム検証は完全性チェックとして継続、真正性は署名 + 公証で保証 (#114)
- **`docs/dev/packaging.md`** — ad-hoc 署名手順を Developer ID + 公証フローに全面更新。正典レシピをローカル `scripts/build-release.sh` に変更
- **auto-release CI** — ad-hoc 署名 DMG の生成・添付を廃止（未署名アーティファクトを「リリース」として公開しないため）。CI はリリースノートのみ作成し、DMG は `scripts/build-release.sh` で生成して添付する。CI での Developer ID 署名は #159

### Upgrade note
- **v1.7.x 以前からのアップデート時、初回のみ Keychain の承認ダイアログがキーごとに再表示されます**。署名が ad-hoc から Developer ID に変わり、既存 Keychain アイテムの ACL から見て「別のアプリ」になるためです。各ダイアログで「常に許可」を選べば、以後はアプリを更新しても再承認は発生しません（署名 ID が Team `34J49FY7U7` で安定するため）

## npm `aikeychain@0.5.1` - 2026-07-09

Republish carrying fixes merged to `main` after the `0.5.0` release.

### Fixed
- **CLI mask leak** — `cli/src/keychain.js` `maskValue` printed `****** (N chars)`, leaking the secret's character count. Now emits a fixed-length `********` mask, matching the `scripts/akc` behavior fixed earlier under #115/#123 (#136)
- **Manual key-retrieval guidance** — `akc init` template, MCP `usage_guide`, and README taught only the `security find-generic-password -s "ENV_VAR_NAME" -w` form, which returns exit 44 for keys stored via the AI KeyChain GUI (`service=com.aieo.aikeychain`) and falsely suggested the key was missing. `akc get <KEY>` is now the primary recommendation everywhere; both `security` lookup forms are documented with an explicit warning that exit 44 on the bare form is not proof of "unregistered" (#137, #138)

## [1.7.0] - 2026-07-16

### Added
- **CLI で追加したキーの GUI 表示** — `akc set`（CLI）で追加したキーは GUI と同じ Keychain（`service=com.aieo.aikeychain`）に保存されるが、GUI 一覧はプリセット + カスタム索引しか反復せず表示されなかった。GUI 起動時に Keychain を列挙し、プリセット/カスタムのどちらにも属さないキーを新カテゴリ「コマンド追加」(`CLI Added`) で発見表示する。分類/アイコンの編集は override で永続化し、内部用（共有鍵/署名鍵）や env 変数名でないアカウントは除外する (#153)

### Fixed
- **`SetupManager.configure()` のマーカーブロック正規化** — 現行ブロックが存在すると早期 return するため、重複した well-formed ブロックや余分な malformed マーカーが残存しても検証・除去されなかった（冪等性・整合性の穴）。早期 return を「well-formed かつ現行と同一ブロックがちょうど 1 つ」に厳格化し、逸脱時は `unconfigure()` 契約（well-formed は全除去して再追加 / malformed は 0600 backup + throw）で整理し直す。ブロック外のユーザー行や連続空行、CRLF 改行を保持する (#148)

### Docs
- **設計書のキー解決フロー最新化** — `docs/design/architecture.md` を現行実装に同期。External CLI を npm CLI(`aikeychain`/`akc`) + MCP server + Bash 同等に更新、Secret Reference の 2 段ルックアップ(#91)を図に反映、AI エージェント経由(MCP + `akc run`)のデータフローを新設 (#156)

## [1.6.1] - 2026-05-13

### Fixed
- **`akc` CLI** — `keychain://KEY_NAME` references registered via the AI KeyChain GUI (stored under `service=com.aieo.aikeychain` / `account=<KEY_NAME>`) could not be resolved by `akc run`; only manually-registered keys (`service=<KEY_NAME>` / `account=$USER`) were looked up. `resolve_keychain` now checks the GUI scheme first and falls back to the manual scheme, so Secret Reference mode works end-to-end with keys added through the app (#90)
- **`MARKETING_VERSION` drift** — `project.yml` and the generated `AIkeychain.xcodeproj` had been frozen at `1.0.0` even though the project was released as `v1.5.1` / `v1.6.0`. Bumped to `1.6.1` to align with the Git tag and CHANGELOG. `scripts/akc` `VERSION` is now also aligned to the app version

## [1.6.0] - 2026-04-21

### Added
- **Secret Reference mode** — Third key management mode (`keychain://KEY_NAME` references in `.zshrc` resolved at runtime by `akc run`). Equivalent to 1Password's `op://` workflow; never exposes key values in parent shell env (#58)
- **`akc` CLI** (`scripts/akc`) — Bash resolver that scans env for `keychain://` references and injects resolved values into a child process via `exec`. Supports `--dry-run` to mask values (#58)
- **Activity log monitor** — `ActivityView` displays per-request history of proxy traffic (timestamp, host, method, path, status, latency) in real time. Today's request / error counts surfaced (#22, #55)
- **`ProxyLogStore`** — In-memory ring of `ProxyLog` entries; never persisted to disk; tokens and request bodies are not recorded
- **English UI (i18n)** — All hardcoded Japanese strings replaced with `L10n.t(...)` lookups (81+ sites); language toggle (`AppLanguage.ja` / `.en`) added to onboarding and to a toolbar menu in the main window (#67)
- **3-mode onboarding** — `OnboardingStep.language` step prepended (now 6 steps); `ModeSelectView` rebuilt to compare three cards with expandable detail and animated diagrams (#61, #62, #66)
- **3-mode comparison page** — Documentation + in-app help describing how keys reach tools and where they appear (env vs. memory vs. neither) (#66)
- **Session token authentication on proxy** — Proxy generates a per-session UUID at start; clients must present it via `X-AIKeyChain-Token`. Token written to `~/.aikeychain_proxy` as `AIKEYCHAIN_SESSION_TOKEN`. Prevents abuse from co-resident localhost processes
- **Xcode test target** — Unit tests added to project bundle and runnable from Xcode (#84)

### Changed
- **README** — Adds three-mode comparison table (English / Japanese)
- **Proxy response forwarding** — Switched to a buffered model to fix streaming / partial-response error handling
- **`MenuBar` / `MainView` / `RecoveryView`** — Replaced binary `isProxyMode` checks with full 3-mode awareness so Standard / Secret Reference / Proxy each render correctly
- **`ZshrcExporter`** — Adds `Secret Reference` export format alongside `.zshrc` and `.env`
- **Mode comparison UI** — Expanded tap targets on mode cards and comparison links

### Fixed
- New-key form: initial service / category selection and save behavior (#68, #69, #70)
- `ModeSelectView`: comparison detail caused unscrollable sheet; corrupted icons (#66 follow-up)
- Language switch: change was not reflected immediately in some screens
- `envVarName` validation in editor; removed dead code paths (#73)

### Security
- **Codex-driven security pass** (#74–#79): mandatory session token enforcement, prevention of upstream secret leakage on parser errors, hardened streaming error responses, plus tightened entitlements documentation
- **esbuild upgrade** to 0.25.0+ via `npm overrides` (vendor advisory)
- Evidence screenshots scrubbed of personal information (cropped / removed / re-captured)

### Documentation
- v1.6.0 test specification + final verification evidence (26/26 ALL PASS) — published at `/test/v1.6.0-final` (#72, #84)
- Packaging guide includes entitlements walkthrough

### Tooling
- Test harness: 200 OK and error-path coverage for proxy (#84)

## [1.5.1] - 2026-03-31

First public release on GitHub.

### Added
- **4-step env import wizard** — Paste `env` output, auto-scan recognized keys, preview, and bulk-import to Keychain (#35, #38, #39, #40, #45, #46, #47)
- **Custom keys & custom categories** — User-defined env var names and categories with editable icons / colors; per-key category overrides for preset services (#36, #41, #42, #43)
- **AI Web auth tracking** — Track web-login services (Anthropic Console, OpenAI Platform, Google AI Studio, Hugging Face, Replicate) alongside API keys
- **Edit-screen category change** — Move a key between categories from the editor
- **Encrypted device-to-device key transfer** — `KeyShareService` uses P-256 ECDH + HKDF-SHA256 + AES-256-GCM with ephemeral keys (forward secrecy). `ShareKeysView` provides a 3-tab UI (My Keys / Send / Receive) (#48, #49, #51, #52)
- **Header proxy status badge** — Toolbar surfaces proxy state in the main window; MenuBar interactions improved (#44, #52)
- **Terms-of-service acknowledgment for key transfer** — User confirms personal-use intent before exporting keys
- **VitePress design site + Cloudflare Pages / GitHub Pages deployment**
- **Auto-release GitHub Actions workflow** + packaging guide
- **CodeQL static analysis workflow**
- **Community health files** (CONTRIBUTING / CODE_OF_CONDUCT / SECURITY)
- **License + disclaimer** — MIT with explicit "AS IS" disclaimer covering API key leakage, charges, and data loss
- **v1.5.1 test specification + proxy integration test evidence** (#28, #23)

### Changed
- **Architecture documentation** rewritten to match the shipped implementation (#53)
- **Repository public-release preparation** — README / CHANGELOG / LICENSE / cleanup pass (#37)

### Security
- **esbuild dependency upgrade** to address a moderate-severity advisory (npm `overrides`)
- Evidence captures sanitized to exclude any token values

## [1.1.0] - 2026-03-25

### Added
- **Standard / Proxy mode selection** — Users choose between simple Keychain export or secure proxy mode at first launch
- **Proxy consent screen** — Proxy mode requires explicit agreement with risk acknowledgment
- **Recovery Guide** — Built-in troubleshooting with step-by-step recovery commands, accessible from menu bar and Help menu
- **Shell Cleanup tool** — Guided commands to find and remove hardcoded API keys from `.zshrc`
- **Proxy lifecycle management** — Env file (`~/.aikeychain_proxy`) auto-created on proxy start, auto-deleted on stop
- **Forced shutdown protection** — Shell hook checks port liveness before sourcing proxy config; stale files auto-cleaned
- **Port configuration UI** — Change proxy port from menu bar, setup screen, and onboarding
- **Port persistence** — Selected port saved in UserDefaults, restored on app launch
- **Animated onboarding mode comparison** — Side-by-side cards with flow diagrams that animate on selection
- **Mode-aware completion screen** — Onboarding completion shows mode-specific instructions
- **Graphical DMG installer** — Background image with drag-to-Applications visual guide
- **App icon in DMG** — `.icns` properly bundled in `.app`
- **Ad-hoc code signing** — Prevents "app is damaged" error on install

### Changed
- **Default port**: 9999 → 18121 (avoids common conflicts)
- **No auto-write to `.zshrc`** — Proxy config is never written to `.zshrc` directly; managed via lifecycle file
- **Menu bar**: Shows mode indicator (Standard/Proxy), proxy controls only visible in Proxy mode
- **Help view**: Added ECONNREFUSED recovery steps and mode switching instructions

### Fixed
- **ECONNREFUSED on Claude** — Caused by `ANTHROPIC_BASE_URL=http://localhost:9999` persisting in `.zshrc` when proxy was not running
- **HelpView hardcoded port** — All `9999` references replaced with dynamic port display
- **Test flakiness** — SetupManager tests serialized to avoid file race conditions

### Security
- Proxy accepts connections from `localhost` only (`acceptLocalOnly = true`)
- Auth headers (`Authorization`, `x-api-key`) stripped from incoming requests before injection
- API keys never written to environment variables in Proxy mode

## [1.0.0] - 2026-03-23

### Added
- **macOS Keychain integration** — CRUD operations via Security.framework
- **Auth proxy server** — Local `NWListener` proxy that reads keys from Keychain and injects auth headers
- **Supported services** — Anthropic, OpenAI, xAI, GitHub, GitLab, Cloudflare, Tailscale, Discord, Slack, Qiita, Higgsfield
- **Proxy routing** — Automatic route matching for `api.anthropic.com`, `api.openai.com`, `api.x.ai`
- **Menu bar resident** — Proxy status, request count, start/stop control
- **Onboarding wizard** — 5-step tutorial (Welcome → How It Works → Register Keys → Shell Setup → Complete)
- **Key editor** — Add, edit, delete keys with token prefix validation
- **Category sidebar** — Filter keys by AI, Code & Git, Cloud, Communication, Dev Tools
- **Export** — Generate `.zshrc` or `.env` format (no key values in output)
- **Help view** — User manual with troubleshooting guide
- **Launch at Login** — `SMAppService` integration
- **Design documentation** — VitePress site at aikeychain.pages.dev

### Architecture
- SwiftUI + Observation framework (`@Observable`)
- MVVM pattern (ViewModels for key list, key editor, onboarding)
- `KeychainService` protocol with mock for testing
- `HTTPRequestParser` for raw HTTP parsing
- `ProxyRoute` for host-based routing with per-service auth header format

## [0.1.0] - 2026-03-22

### Added
- Project scaffolding (Swift Package Manager + XcodeGen)
- VitePress documentation site with architecture, data model, UI/UX, and security design
- Cloudflare Pages deployment
- README with project overview
