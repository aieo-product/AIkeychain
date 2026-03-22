# データモデル設計

> GitHub Issue: [#2 データモデル設計](https://github.com/aieo-product/AIkeychain/issues/2)

## モデル関連図

```
┌──────────────┐       ┌──────────────┐
│  APIKey      │──────▶│ ServiceType  │
│              │       │              │
│  id          │       │  anthropic   │
│  service ────┼──────▶│  openai      │
│  envVarName  │       │  github      │
│  isConfigured│       │  ...         │
└──────────────┘       └──────┬───────┘
                              │
                              │ category
                              ▼
                       ┌──────────────┐
                       │ KeyCategory  │
                       │              │
                       │  ai          │
                       │  codeAndGit  │
                       │  cloud       │
                       │  communication│
                       │  devTools    │
                       └──────────────┘
```

## ServiceType

アプリが管理する全サービスの定義。

```
┌──────────────────────────────────────────────────────┐
│                   ServiceType                        │
├──────────────────────────────────────────────────────┤
│                                                      │
│  AI API ─────┬── anthropic   (sk-ant-*)              │
│              ├── openai      (sk-*)                  │
│              ├── xai         (xai-*)                 │
│              ├── googleai    (AIza*)                  │
│              └── higgsfield                           │
│                                                      │
│  Code & Git ─┬── github      (ghp_* / gho_*)        │
│              └── gitlab      (glpat-*)               │
│                                                      │
│  Cloud ──────┬── cloudflare                          │
│              └── tailscale   (tskey-*)               │
│                                                      │
│  Comm ───────┬── discord                             │
│              └── slack       (xapp-* / xoxb-*)       │
│                                                      │
│  DevTools ───└── qiita                               │
│                                                      │
└──────────────────────────────────────────────────────┘
```

### プロパティ

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `displayName` | String | "Anthropic (Claude)" |
| `envVarName` | String | "ANTHROPIC_API_KEY" |
| `category` | KeyCategory | .ai |
| `tokenPrefix` | String? | "sk-ant-" |
| `setupURL` | URL? | トークン発行ページ |
| `systemImage` | String | SF Symbols名 |

### サービス定義一覧

| Service | displayName | envVarName | tokenPrefix | category |
|---------|------------|------------|-------------|----------|
| anthropic | Anthropic (Claude) | ANTHROPIC_API_KEY | `sk-ant-` | ai |
| openai | OpenAI (GPT) | OPENAI_API_KEY | `sk-` | ai |
| xai | xAI (Grok) | XAI_API_KEY | `xai-` | ai |
| googleai | Google AI (Gemini) | GOOGLE_AI_API_KEY | `AIza` | ai |
| higgsfield | Higgsfield | HIGGSFIELD_API_KEY | - | ai |
| github | GitHub | GITHUB_TOKEN | `ghp_` | codeAndGit |
| gitlab | GitLab | GITLAB_TOKEN | `glpat-` | codeAndGit |
| cloudflare | Cloudflare | CLOUDFLARE_API_TOKEN | - | cloud |
| tailscale | Tailscale | TAILSCALE_AUTH_KEY | `tskey-` | cloud |
| discord | Discord | DISCORD_TOKEN | - | communication |
| slack | Slack | SLACK_APP_TOKEN | `xapp-` | communication |
| qiita | Qiita | QIITA_TOKEN | - | devTools |

## KeyCategory

```swift
enum KeyCategory: String, CaseIterable, Identifiable {
    case ai
    case codeAndGit
    case cloud
    case communication
    case devTools
}
```

| Category | displayName | systemImage | accentColor |
|----------|------------|-------------|-------------|
| ai | AI API | brain.head.profile | Purple (#7C3AED) |
| codeAndGit | Code & Git | chevron.left.forwardslash.chevron.right | Orange (#EA580C) |
| cloud | Cloud & Infra | cloud.fill | Blue (#0284C7) |
| communication | Communication | bubble.left.and.bubble.right.fill | Green (#059669) |
| devTools | Developer Tools | wrench.and.screwdriver.fill | Gray (#6B7280) |

## APIKey

```swift
struct APIKey: Identifiable {
    let id: UUID
    let service: ServiceType
    var envVarName: String
    var isConfigured: Bool  // Keychain に値が存在するか (算出)
}
```

::: warning 設計ポイント
- **シークレット値はモデルに持たない**: 表示時に都度 Keychain から取得
- **isConfigured は算出**: `KeychainService.exists(for:)` の結果
- **ServiceType が全ての表示情報を提供**: APIKey は薄いラッパー
:::

## OnboardingStep

```swift
enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case githubToken    // 必須
    case aiKeys         // 推奨 (スキップ可)
    case otherKeys      // 任意 (スキップ可)
    case completion
}
```
