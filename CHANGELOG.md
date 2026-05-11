# Changelog

All notable changes to AI KeyChain are documented in this file.

## [Unreleased]

### Fixed
- **`akc` CLI** — `keychain://KEY_NAME` references registered via the AI KeyChain GUI (stored under `service=com.aieo.aikeychain` / `account=<KEY_NAME>`) could not be resolved by `akc run`; only manually-registered keys (`service=<KEY_NAME>` / `account=$USER`) were looked up. `resolve_keychain` now checks the GUI scheme first and falls back to the manual scheme, so Secret Reference mode works end-to-end with keys added through the app

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
