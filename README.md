<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014+-blue?style=for-the-badge&logo=apple" />
  <img src="https://img.shields.io/badge/Swift-5.9+-orange?style=for-the-badge&logo=swift" />
  <img src="https://img.shields.io/badge/SwiftUI-Native-purple?style=for-the-badge" />
  <img src="https://img.shields.io/badge/license-MIT-green?style=for-the-badge" />
</p>

# AI KeyChain

> AI開発者のための macOS ネイティブ鍵管理アプリ

AI KeyChain は、AI開発で必要となる各種APIキー・トークンを **macOS Keychain** で安全に一元管理するネイティブアプリです。

## なぜ AI KeyChain？

AI開発では多数のAPIキーを扱います:

```
Anthropic (Claude API)  →  sk-ant-api03-xxxxx
OpenAI (GPT API)        →  sk-xxxxx
xAI (Grok API)          →  xai-xxxxx
Google AI (Gemini)      →  AIzaxxxxx
GitHub / GitLab         →  ghp_xxxxx / glpat-xxxxx
Cloudflare              →  xxxxx
...
```

これらを `.env` や `.zshrc` に平文で保存していませんか？

**AI KeyChain** は macOS Keychain の暗号化ストレージを活用し、セキュアかつ簡単にキーを管理します。

## 特徴

```
┌─────────────────────────────────────────────────────────────┐
│                      AI KeyChain                            │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  🔐 macOS Keychain        暗号化された安全なストレージ       │
│  🤖 AI API 特化           主要AIサービスをプリセット対応     │
│  🎓 ガイド付きセットアップ  初回起動時のチュートリアル        │
│  📋 ワンクリックexport     .zshrc / .env 形式で出力         │
│  🎨 ネイティブUI           SwiftUI によるmacOS体験          │
│  👥 チーム導入対応          社内展開を想定した設計            │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## 対応サービス

| カテゴリ | サービス |
|---------|---------|
| **AI API** | Anthropic (Claude) / OpenAI (GPT) / xAI (Grok) / Google AI (Gemini) / Higgsfield |
| **Code & Git** | GitHub / GitLab |
| **Cloud & Infra** | Cloudflare / Tailscale |
| **Communication** | Discord / Slack |
| **Developer Tools** | Qiita |

## アーキテクチャ

```
┌──────────────────────────────────────────────────┐
│                   AI KeyChain App                 │
│                                                   │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────┐ │
│  │ Onboarding  │  │   Main View  │  │ Export  │  │
│  │   Flow      │→ │  Key Manager │→ │ .zshrc  │  │
│  └─────────────┘  └──────────────┘  └─────────┘ │
│         │                │                │       │
│         └────────┬───────┘                │       │
│                  ▼                        ▼       │
│  ┌──────────────────────────────────────────────┐│
│  │          KeychainService (Security.framework) ││
│  └──────────────────────────────────────────────┘│
│                        │                          │
└────────────────────────┼──────────────────────────┘
                         ▼
              ┌─────────────────────┐
              │   macOS Keychain    │
              │  (暗号化ストレージ)  │
              └─────────────────────┘
```

## オンボーディングフロー

```
Welcome → GitHub Token (必須) → AI API Keys (推奨) → その他 (任意) → 完了
   │          │                      │                    │           │
   │     バリデーション付き      Anthropic/OpenAI/     GitLab等    メイン画面へ
   │     スキップ不可           xAI をまとめて案内   スキップ可能
```

## 開発スタック

- **言語**: Swift 5.9+
- **UI**: SwiftUI (macOS 14 Sonoma+)
- **状態管理**: Observation framework (`@Observable`)
- **セキュリティ**: Security.framework (Keychain Services API)
- **ビルド**: Xcode 15+
- **配布**: DMG / Homebrew Cask (予定)

## ロードマップ

- [x] コンセプト設計
- [ ] Phase 1: プロジェクト基盤構築
- [ ] Phase 2: コア機能実装 (Keychain CRUD / メイン画面)
- [ ] Phase 3: オンボーディング / UI仕上げ
- [ ] Phase 4: テスト・リリース

## ライセンス

MIT License

## 開発ブログ

開発の全工程を技術ブログで発信しています。(準備中)
