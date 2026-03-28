# Changelog

All notable changes to AI KeyChain are documented in this file.

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
