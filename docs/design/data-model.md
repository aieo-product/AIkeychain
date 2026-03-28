# データモデル設計

> GitHub Issue: [#2 データモデル設計](https://github.com/aieo-product/AIkeychain/issues/2) → [#53 設計書更新](https://github.com/aieo-product/AIkeychain/issues/53)

## モデル関連図

```mermaid
erDiagram
    APIKey ||--o| ServiceType : "preset"
    APIKey ||--o| CustomKey : "custom"
    ServiceType ||--|| KeyCategory : "belongs to"
    CustomKey ||--|| CustomCategory : "belongs to"
    CustomKeyStore ||--|{ CustomKey : "manages"
    CustomKeyStore ||--|{ CustomCategory : "manages"
    ProxyRoute ||--|| ServiceType : "routes"

    APIKey {
        UUID id
        ServiceType service "optional"
        CustomKey customKey "optional"
        String envVarName
        Bool isConfigured
    }

    ServiceType {
        String displayName
        String envVarName
        KeyCategory category
        String tokenPrefix "optional"
        URL setupURL "optional"
        String systemImage
        Bool isWebAuth
        URL loginURL "optional"
    }

    KeyCategory {
        String rawValue "display name"
        Color color
        String systemImage
    }

    CustomKey {
        UUID id
        String envVarName
        String displayName
        UUID categoryId
    }

    CustomCategory {
        UUID id
        String name
        String systemImage
        String colorHex
    }

    ProxyRoute {
        String host
        String targetScheme
        String keychainAccount
        String headerName
        String headerValuePrefix
    }
```

## ServiceType

20 サービスを 6 カテゴリに分類。

### プロパティ

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `displayName` | String | UI 表示名 |
| `envVarName` | String | 環境変数名 |
| `category` | KeyCategory | 所属カテゴリ |
| `tokenPrefix` | String? | 期待されるトークンプレフィックス |
| `setupURL` | URL? | トークン発行ページ |
| `systemImage` | String | SF Symbols 名 |
| `isWebAuth` | Bool | Web 認証タイプかどうか |
| `loginURL` | URL? | Web ログインページ |

### サービス定義一覧

#### AI API

| Service | displayName | envVarName | tokenPrefix | category |
|---------|------------|------------|-------------|----------|
| anthropic | Anthropic (Claude) | ANTHROPIC_API_KEY | `sk-ant-` | ai |
| openAI | OpenAI (GPT) | OPENAI_API_KEY | `sk-` | ai |
| xAI | xAI (Grok) | XAI_API_KEY | `xai-` | ai |
| higgsfield | Higgsfield | HIGGSFIELD_API_KEY | - | ai |

#### AI Web (Web 認証)

| Service | displayName | envVarName | loginURL |
|---------|------------|------------|----------|
| anthropicWeb | Anthropic Web | ANTHROPIC_WEB_AUTH | claude.ai |
| openAIWeb | OpenAI Platform | OPENAI_WEB_AUTH | platform.openai.com |
| googleAIStudio | Google AI Studio | GOOGLE_AI_STUDIO_AUTH | aistudio.google.com |
| huggingFace | Hugging Face | HUGGINGFACE_AUTH | huggingface.co |
| replicateWeb | Replicate | REPLICATE_AUTH | replicate.com |

#### Code & Git

| Service | displayName | envVarName | tokenPrefix |
|---------|------------|------------|-------------|
| github | GitHub | GITHUB_TOKEN | `ghp_` |
| gitlab | GitLab | GITLAB_TOKEN | `glpat-` |

#### Cloud & Infra

| Service | displayName | envVarName | tokenPrefix |
|---------|------------|------------|-------------|
| cloudflareAPI | Cloudflare API | CLOUDFLARE_API_TOKEN | - |
| cloudflareAccount | Cloudflare Account | CLOUDFLARE_ACCOUNT_ID | - |
| tailscale | Tailscale | TAILSCALE_AUTH_KEY | `tskey-` |

#### Communication

| Service | displayName | envVarName | tokenPrefix |
|---------|------------|------------|-------------|
| discord | Discord | DISCORD_TOKEN | - |
| slack | Slack | SLACK_APP_TOKEN | `xapp-` |

#### Developer Tools

| Service | displayName | envVarName | tokenPrefix |
|---------|------------|------------|-------------|
| qiita | Qiita | QIITA_TOKEN | - |

## KeyCategory

6 つのビルトインカテゴリ。

```swift
enum KeyCategory: String, CaseIterable, Identifiable {
    case ai = "AI API"
    case webAuth = "AI Web"
    case codeAndGit = "Code & Git"
    case cloud = "Cloud & Infra"
    case communication = "Communication"
    case devTools = "Developer Tools"
}
```

| Category | color | systemImage | Hex |
|----------|-------|-------------|-----|
| ai | Purple | brain.head.profile | `#7C3AED` |
| webAuth | Pink | globe | `#DB2777` |
| codeAndGit | Orange | chevron.left.forwardslash.chevron.right | `#EA580C` |
| cloud | Blue | cloud.fill | `#0284C7` |
| communication | Green | bubble.left.and.bubble.right.fill | `#059669` |
| devTools | Gray | wrench.and.screwdriver.fill | `#6B7280` |

## APIKey

プリセットサービスとカスタムキーの両方を統一的に扱うモデル。

```swift
struct APIKey: Identifiable {
    let id: UUID
    let service: ServiceType?      // プリセットの場合
    let customKey: CustomKey?       // カスタムの場合
    var envVarName: String
    var isConfigured: Bool          // Keychain に値が存在するか
}
```

### 算出プロパティ

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `displayName` | String | service?.displayName ?? customKey?.displayName |
| `systemImage` | String | サービスまたはカテゴリのアイコン |
| `categoryColor` | Color | 所属カテゴリの色 |
| `setupURL` | URL? | トークン発行ページ (プリセットのみ) |
| `tokenPrefix` | String? | プレフィックス (プリセットのみ) |
| `isCustom` | Bool | customKey != nil |

### 初期化パターン

```swift
// プリセットキー
APIKey(service: .anthropic)
// → envVarName = "ANTHROPIC_API_KEY", displayName = "Anthropic (Claude)"

// カスタムキー
APIKey(customKey: CustomKey(envVarName: "MY_KEY", displayName: "My Key", categoryId: ...))
```

::: warning 設計ポイント
- **シークレット値はモデルに持たない**: 表示時に都度 Keychain から取得
- **isConfigured は stored property**: Keychain アクセスのパフォーマンスを考慮し、`loadKeys()` 時に一括チェック
- **デュアル初期化**: service / customKey の排他的なオプショナルで柔軟性を確保
:::

## CustomKeyStore

ユーザー定義のカテゴリとキーを管理するシングルトン。

```swift
final class CustomKeyStore {
    static let shared = CustomKeyStore()

    var categories: [CustomCategory]     // ユーザー定義カテゴリ
    var keys: [CustomKey]                // ユーザー定義キー
    var categoryOverrides: [String: ...]  // プリセットキーのカテゴリ変更
}
```

| データ | 永続化 | キー |
|--------|--------|------|
| categories | UserDefaults (JSON) | `"custom_categories"` |
| keys | UserDefaults (JSON) | `"custom_keys"` |
| categoryOverrides | UserDefaults (JSON) | `"category_overrides"` |

## ProxyRoute

プロキシサーバーのルーティングテーブル。静的定義。

```swift
struct ProxyRoute {
    let host: String              // "api.anthropic.com"
    let targetScheme: String      // "https"
    let keychainAccount: String   // "ANTHROPIC_API_KEY"
    let headerName: String        // "x-api-key"
    let headerValuePrefix: String // "" or "Bearer "

    static func route(for host: String) -> ProxyRoute?
}
```

| Host | keychainAccount | headerName | headerValuePrefix |
|------|----------------|------------|-------------------|
| api.anthropic.com | ANTHROPIC_API_KEY | x-api-key | (なし) |
| api.openai.com | OPENAI_API_KEY | Authorization | Bearer |
| api.x.ai | XAI_API_KEY | Authorization | Bearer |

## OnboardingStep

5 段階のオンボーディングウィザード。

```swift
enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case modeSelect       // Standard / Proxy 選択
    case registerKeys     // キー登録案内 (スキップ可)
    case setupShell       // シェル設定 (スキップ可)
    case completion
}
```

| Step | title | canSkip |
|------|-------|---------|
| welcome | "AI KeyChain へようこそ" | false |
| modeSelect | "モード選択" | false |
| registerKeys | "キー登録" | true |
| setupShell | "シェル設定" | true |
| completion | "セットアップ完了" | false |
