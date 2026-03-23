# AI KeyChain セッションログ

> Session: envKeychain (2026-03-22)

## 実施済み作業

### 1. macOS Keychain セットアップ
- `.zshrc` の平文トークンを macOS Keychain に移行
- `security add-generic-password` で暗号化保存
- `.zshrc` を Keychain 参照方式 (`security find-generic-password`) に書き換え

#### 登録済みキー (11件 + X API 5件)
| 環境変数名 | Keychain Service名 | 用途 |
|---|---|---|
| CLOUDFLARE_API_TOKEN | CLOUDFLARE_API_TOKEN | Cloudflare API |
| CLOUDFLARE_ACCOUNT_ID | CLOUDFLARE_ACCOUNT_ID | Cloudflare アカウント |
| GITLAB_TOKEN | GITLAB_TOKEN | GitLab |
| GITHUB_TOKEN | GITHUB_TOKEN | GitHub |
| DISCORD_TOKEN | DISCORD_TOKEN | Discord Bot |
| QIITA_TOKEN | QIITA_TOKEN | Qiita CLI |
| ANTHROPIC_API_KEY | ANTHROPIC_API_KEY | Claude API (tiktoclaw) |
| HIGGSFIELD_API_KEY | HIGGSFIELD_API_KEY | Higgsfield |
| TAILSCALE_AUTH_KEY | TAILSCALE_AUTH_KEY | Tailscale |
| SLACK_APP_TOKEN | SLACK_APP_TOKEN | jcarvis Slack App Socket |
| XAI_API_KEY | XAI_API_KEY | X AI (Grok) |
| X_POCOLOCO_CONSUMER_KEY | *(ユーザーが別セッションで追加)* | X API (POCOLOCO) |
| X_POCOLOCO_CONSUMER_SECRET | *(同上)* | X API (POCOLOCO) |
| X_POCOLOCO_BEARER_TOKEN | *(同上)* | X API (POCOLOCO) |
| X_POCOLOCO_ACCESS_TOKEN | *(同上)* | X API (POCOLOCO) |
| X_POCOLOCO_ACCESS_TOKEN_SECRET | *(同上)* | X API (POCOLOCO) |

### 2. CLAUDE.md 秘密鍵ルール追加
- `/Users/y_ito/Documents/WorkSpace/otani/CLAUDE.md` に秘密鍵取り扱いルールを追記
- 全セッション共通で `.env` 平文展開を禁止
- Keychain 参照方式のみ許可

### 3. GitHub リポジトリ作成・Issue整備
- リポジトリ: `git@github.com:aieo-product/AIkeychain.git`
- README 作成・push済み

#### Issue 一覧 (18件)

**Phase 1: 設計・基盤**
| # | タイトル | ラベル | 状態 |
|---|---------|--------|------|
| #1 | アプリケーションアーキテクチャ設計書 | design, phase-1 | Open |
| #2 | データモデル設計 - APIKey / ServiceType / KeyCategory | design, phase-1 | Open |
| #3 | UI/UXデザイン - 画面設計とビジュアルガイドライン | design, ui/ux, phase-1 | Open |
| #4 | Xcodeプロジェクト初期セットアップ | infrastructure, phase-1 | Open |
| #15 | セキュリティ設計書 - 脅威モデルと対策 | design, phase-1 | Open |

**Phase 2: コア機能**
| # | タイトル | ラベル | 状態 |
|---|---------|--------|------|
| #5 | KeychainService - macOS Keychain CRUD操作 | feature, phase-2 | Open |
| #6 | Theme定義 - カラー・フォント・アニメーション | feature, ui/ux, phase-2 | Open |
| #7 | メイン画面 - NavigationSplitView キー一覧 | feature, phase-2 | Open |
| #8 | キー編集画面 - 追加・編集・削除 | feature, phase-2 | Open |
| #10 | Export機能 - .zshrc / .env 形式出力 | feature, phase-2 | Open |

**Phase 3: UI/オンボーディング**
| # | タイトル | ラベル | 状態 |
|---|---------|--------|------|
| #9 | オンボーディング - チュートリアルフロー | feature, phase-3 | Open |
| #11 | ContentView - オンボーディング/メイン画面切替ルーター | feature, phase-3 | Open |
| #18 | アプリアイコン作成 | ui/ux, phase-3 | Open |

**Phase 4: テスト・リリース**
| # | タイトル | ラベル | 状態 |
|---|---------|--------|------|
| #12 | ユニットテスト・UIテスト | testing, phase-4 | Open |
| #13 | ビルド・配布準備 (DMG / Homebrew) | release, phase-4 | Open |
| #16 | CI/CD - GitHub Actions ビルド・テスト自動化 | infrastructure, phase-4 | Open |

**その他**
| # | タイトル | ラベル | 状態 |
|---|---------|--------|------|
| #14 | 技術ブログ連載計画 - 全工程の発信 | documentation, blog | Open |
| #17 | 4/10 LT登壇資料準備 | documentation, blog | Open |

### 4. VitePress 設計書サイト
- Cloudflare Pages にデプロイ: **https://aikeychain.pages.dev**
- **Cloudflare Access で private化済み** (`@aieo.co.jp` ドメインのみ)
- Access Application ID: `2e5bfcad-704c-4a91-9a13-60575765867b`

#### 設計書ページ
| ページ | パス |
|--------|------|
| ホーム | `/docs/index.md` |
| アーキテクチャ設計 | `/docs/design/architecture.md` |
| データモデル設計 | `/docs/design/data-model.md` |
| UI/UXデザイン | `/docs/design/ui-ux.md` |
| セキュリティ設計 | `/docs/design/security.md` |
| 開発セットアップ | `/docs/dev/index.md` |
| ロードマップ | `/docs/dev/roadmap.md` |
| ユーザーガイド | `/docs/guide/index.md` |

### 5. draw.io 図 (6枚)
`.drawio` ソースと `.svg` エクスポート版を `/docs/assets/diagrams/` に格納。

| ファイル | 内容 |
|---------|------|
| architecture.drawio/svg | レイヤーアーキテクチャ図 |
| data-model.drawio/svg | データモデル関連図 (UML) |
| data-flow.drawio/svg | データフロー (Write/Read) |
| onboarding-flow.drawio/svg | オンボーディングフロー |
| main-screen.drawio/svg | メイン画面ワイヤーフレーム |
| security-threat-model.drawio/svg | 脅威モデル + 比較表 |

### 6. 類似ツール調査結果
AI API キー管理に特化した macOS ネイティブ (SwiftUI) アプリは**既存で存在しない**ことを確認。
- Secretive: SSH鍵専用
- 1Password: 有料
- EnvKey: Electron (非ネイティブ)
- ks: CLI のみ

---

## 未実施・次のアクション

### 最優先 (明日中に完成目標)
1. **Issue #4**: Xcodeプロジェクト初期セットアップ
2. **Issue #5**: KeychainService 実装
3. **Issue #6**: Theme 定義
4. **Issue #7**: メイン画面実装
5. **Issue #8**: キー編集画面実装

### 次に
6. **Issue #9**: オンボーディング実装
7. **Issue #11**: ContentView ルーター
8. **Issue #10**: Export機能
9. **Issue #12**: テスト
10. **Issue #13**: リリースビルド (DMG)

### ユーザーからの未回答質問
- Cloudflare Access の許可ドメインが `@aieo.co.jp` で正しいか
- CLAUDE.md に追加したいルールの具体内容

### マイルストーン
| 日付 | 目標 |
|------|------|
| 3/23 | Phase 1-2 完了 (設計 + コア機能) |
| 3/30 | Phase 3 完了 (UI/オンボーディング) |
| 4/5 | Phase 4 完了 (テスト・リリース) |
| **4/10** | **LT 登壇** |

---

## 技術スタック
- Swift 5.9+ / SwiftUI / macOS 14 Sonoma+
- Observation framework (@Observable)
- Security.framework (Keychain Services API)
- VitePress (設計書サイト)
- Cloudflare Pages + Access (ホスティング・認証)

## リポジトリ情報
- GitHub: `aieo-product/AIkeychain`
- 設計書: `https://aikeychain.pages.dev` (private)
- ワーキングディレクトリ: `/Users/y_ito/Documents/WorkSpace/otani/gitlab/aieo/study/AIkeychain`
