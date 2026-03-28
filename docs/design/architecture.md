# アーキテクチャ設計

> GitHub Issue: [#1 アプリケーションアーキテクチャ設計書](https://github.com/aieo-product/AIkeychain/issues/1) → [#53 設計書更新](https://github.com/aieo-product/AIkeychain/issues/53)

## レイヤー構成

```mermaid
graph TB
    subgraph Presentation["Presentation Layer (SwiftUI Views)"]
        direction LR
        MainView["MainView<br/>NavigationSplitView"]
        MenuBarView["MenuBarView<br/>MenuBarExtra"]
        OnboardingView["OnboardingView"]
        EditorView["KeyEditorView"]
        ShareKeysView["ShareKeysView"]
        EnvImportView["EnvImportView"]
        OtherViews["ModeSelect / Cleanup<br/>Recovery / Help<br/>CategoryManager"]
    end

    subgraph ViewModel["ViewModel Layer (@Observable)"]
        direction LR
        KeyListVM["KeyListViewModel"]
        KeyEditorVM["KeyEditorViewModel"]
        OnboardingVM["OnboardingViewModel"]
    end

    subgraph Service["Service Layer"]
        direction LR
        AppState["AppState<br/>(Singleton)"]
        ProxyServer["ProxyServer<br/>(NWListener)"]
        KeychainSvc["KeychainService"]
        SetupMgr["SetupManager"]
        ZshrcExp["ZshrcExporter"]
        KeyShareSvc["KeyShareService<br/>(P-256 ECDH)"]
        HTTPParser["HTTPRequestParser"]
        CustomStore["CustomKeyStore"]
    end

    subgraph System["System Layer"]
        direction LR
        Keychain["macOS Keychain<br/>(Security.framework)"]
        Network["Network.framework<br/>(NWListener)"]
        ServiceMgmt["ServiceManagement<br/>(SMAppService)"]
        CryptoKit["CryptoKit<br/>(P-256 / AES-GCM)"]
    end

    Presentation --> ViewModel
    ViewModel --> Service
    Service --> System

    style Presentation fill:#E8D5FF,stroke:#7C3AED
    style ViewModel fill:#DBEAFE,stroke:#0284C7
    style Service fill:#D1FAE5,stroke:#059669
    style System fill:#FEF3C7,stroke:#F59E0B
```

### レイヤー責務

| レイヤー | 責務 | 主要コンポーネント |
|---------|------|------------------|
| **Presentation** | UI 表示・ユーザー操作受付 | MainView, MenuBarView, OnboardingView, KeyEditorView 他 |
| **ViewModel** | 画面状態管理・ビジネスロジック | KeyListViewModel, KeyEditorViewModel, OnboardingViewModel |
| **Service** | アプリ固有の処理・外部連携 | AppState, ProxyServer, KeychainService, SetupManager, KeyShareService |
| **System** | OS フレームワーク | Security.framework, Network.framework, CryptoKit, ServiceManagement |

## データフロー

### Standard モード

```mermaid
sequenceDiagram
    participant Shell as ユーザー Shell
    participant Zshrc as .zshrc
    participant Security as security コマンド
    participant Keychain as macOS Keychain
    participant API as AI API

    Shell->>Zshrc: source ~/.zshrc
    Zshrc->>Security: security find-generic-password -s "ANTHROPIC_API_KEY" -a "$USER" -w
    Security->>Keychain: SecItemCopyMatching
    Keychain-->>Security: シークレット値
    Security-->>Zshrc: 値を返却
    Zshrc->>Shell: export ANTHROPIC_API_KEY=<値>
    Shell->>API: curl -H "x-api-key: $ANTHROPIC_API_KEY"
```

### Proxy モード

```mermaid
sequenceDiagram
    participant App as ユーザーアプリ
    participant Proxy as ProxyServer<br/>(localhost:18121)
    participant Parser as HTTPRequestParser
    participant Route as ProxyRoute
    participant KS as KeychainService
    participant Keychain as macOS Keychain
    participant API as Upstream API

    App->>Proxy: POST http://localhost:18121/v1/messages
    Proxy->>Parser: 生データをパース
    Parser-->>Proxy: ParsedRequest (host, headers, body)
    Proxy->>Route: route(for: host)
    Route-->>Proxy: ProxyRoute (keychainAccount, headerName)
    Proxy->>KS: retrieve("ANTHROPIC_API_KEY")
    KS->>Keychain: SecItemCopyMatching
    Keychain-->>KS: シークレット値
    KS-->>Proxy: API キー
    Proxy->>API: HTTPS リクエスト + 認証ヘッダー注入
    API-->>Proxy: レスポンス
    Proxy-->>App: レスポンス転送
```

### デバイス間キー転送

```mermaid
sequenceDiagram
    participant A as デバイス A
    participant KS_A as KeyShareService (A)
    participant File as .aikeychain ファイル
    participant KS_B as KeyShareService (B)
    participant B as デバイス B

    A->>KS_A: generateKeyPair()
    KS_A->>KS_A: P-256 秘密鍵を Keychain に保存
    KS_A-->>A: .aikeychain-pub (公開鍵)

    A->>B: 公開鍵ファイルを共有

    B->>KS_B: encryptAndExport(keys, publicKey)
    KS_B->>KS_B: ECDH → HKDF-SHA256 → AES-256-GCM
    KS_B-->>B: .aikeychain (暗号化ファイル)

    B->>A: 暗号化ファイルを共有

    A->>KS_A: decryptAndImport(.aikeychain)
    KS_A->>KS_A: 秘密鍵で ECDH → 復号
    KS_A-->>A: キーを Keychain にインポート
```

## ファイル構成

```
AIkeychain/
├── AIkeychainApp.swift              # エントリポイント (Window + MenuBarExtra)
│
├── Resources/
│   └── AIkeychain.entitlements      # Keychain アクセスグループ + ネットワーク
│
├── Models/
│   ├── APIKey.swift                 # キー情報 (プリセット + カスタム)
│   ├── ServiceType.swift            # 20 サービス定義 (6 カテゴリ)
│   ├── KeyCategory.swift            # 6 カテゴリ定義
│   ├── OnboardingStep.swift         # 5 ステップ定義
│   ├── CustomKeyStore.swift         # カスタムキー・カテゴリ永続化
│   └── ProxyRoute.swift             # プロキシルーティング定義
│
├── Services/
│   ├── AppState.swift               # グローバル状態 (シングルトン, デュアルモード)
│   ├── ProxyServer.swift            # NWListener HTTP プロキシ
│   ├── KeychainService.swift        # Keychain CRUD (Protocol ベース)
│   ├── SetupManager.swift           # .zshrc / プロキシ設定ライフサイクル
│   ├── KeyShareService.swift        # P-256 ECDH + AES-256-GCM キー転送
│   ├── HTTPRequestParser.swift      # HTTP/1.1 リクエストパーサー
│   └── ZshrcExporter.swift          # .zshrc / .env エクスポート生成
│
├── ViewModels/
│   ├── KeyListViewModel.swift       # キー一覧管理・フィルタリング
│   ├── KeyEditorViewModel.swift     # キー追加・編集バリデーション
│   └── OnboardingViewModel.swift    # オンボーディングフロー制御
│
├── Views/
│   ├── Main/
│   │   ├── MainView.swift           # ルート (NavigationSplitView)
│   │   ├── SidebarView.swift        # カテゴリナビゲーション
│   │   ├── KeyListView.swift        # キーグリッド + 検索
│   │   └── KeyRowView.swift         # キーセル
│   ├── Editor/
│   │   └── KeyEditorView.swift      # 追加・編集フォーム
│   ├── Onboarding/
│   │   ├── OnboardingView.swift     # ステップコンテナ
│   │   └── SetupView.swift          # シェル設定ガイド
│   ├── Export/
│   │   └── ExportView.swift         # .zshrc/.env エクスポート
│   ├── MenuBarView.swift            # メニューバーポップオーバー
│   ├── ModeSelectView.swift         # Standard / Proxy 選択
│   ├── ShareKeysView.swift          # 暗号化キー転送 (P-256)
│   ├── EnvImportView.swift          # 4 ステップ env インポート
│   ├── CategoryManagerView.swift    # カスタムカテゴリ管理
│   ├── CleanupView.swift            # .zshrc クリーンアップ
│   ├── RecoveryView.swift           # プロキシ復旧ガイド
│   └── HelpView.swift               # ユーザーマニュアル
│
├── Components/
│   ├── CategoryIcon.swift           # カテゴリアイコン
│   ├── ServiceIcon.swift            # サービスアイコン
│   └── StatusBadge.swift            # 設定済み/未設定バッジ
│
└── Theme/
    ├── AppColors.swift              # カラーパレット
    ├── AppFonts.swift               # タイポグラフィ
    └── AppAnimations.swift          # トランジションアニメーション
```

## 状態管理方針

macOS 14+ の **Observation framework** (`@Observable`) を採用。

### AppState — グローバル状態 (シングルトン)

```swift
@Observable
final class AppState {
    static let shared = AppState()

    var keyManagementMode: KeyManagementMode  // .standard or .proxy
    var proxyPort: UInt16 = 18121
    var proxyServer: ProxyServer
    var hasProxyConsent: Bool
    var launchAtLogin: Bool                   // SMAppService 連携

    func startProxyIfNeeded()                 // アプリ起動時の自動開始
    func stopProxy()                          // プロキシ停止
    func switchMode(to:)                      // モード切替 + プロキシ再起動
    func changePort(to:)                      // ポート変更 + 再起動
}
```

### ViewModel — 画面ごとの状態

```swift
@Observable
final class KeyListViewModel {
    var keys: [APIKey] = []
    var selectedCategory: CategorySelection?
    var searchText: String = ""
    var filteredKeys: [APIKey] { /* カテゴリ + 検索フィルタ */ }

    private let keychainService: KeychainServiceProtocol  // DI 可能
}
```

::: tip なぜ @Observable？
- `ObservableObject` + `@Published` よりパフォーマンスが良い（プロパティ単位の追跡）
- ボイラープレートが少ない
- SwiftUI との統合がよりシンプル
:::

### 永続化戦略

| データ | 保存先 | 理由 |
|--------|--------|------|
| シークレット値 | macOS Keychain | セキュリティ最優先 |
| カスタムキー・カテゴリ | UserDefaults (JSON) | 軽量な構造化データ |
| オンボーディング完了フラグ | UserDefaults | 単純なブール値 |
| モード選択・ポート番号 | UserDefaults | アプリ設定 |
| プロキシ設定 | ~/.aikeychain_proxy | シェルから参照するため |

## エラーハンドリング方針

### Keychain エラー

```swift
enum KeychainError: LocalizedError {
    case duplicateItem
    case itemNotFound
    case invalidData
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .duplicateItem: "キーは既に登録されています"
        case .itemNotFound: "キーが見つかりません"
        case .invalidData: "データ形式が不正です"
        case .unexpectedStatus(let status): "予期しないエラー: \(status)"
        }
    }
}
```

### ProxyServer エラー

| 状況 | ハンドリング |
|------|------------|
| ポート使用中 | `lastError` に記録、MenuBar に表示 |
| 上流 API 接続失敗 | HTTP 502 をクライアントに返却 |
| ルート未定義 | HTTP 404 をクライアントに返却 |
| Keychain 読取失敗 | HTTP 500 + エラーメッセージ返却 |

### SetupManager エラー

| 状況 | ハンドリング |
|------|------------|
| .zshrc 読取失敗 | エラーログ、UI にフォールバック表示 |
| .zshrc 書込失敗 | ユーザーに手動設定を案内 |
| security コマンド失敗 | isConfigured を false に設定 |

::: warning 設計方針
- エラーは可能な限り **ユーザーに可視化** する（MenuBar ステータス、アラート）
- プロキシのエラーは **リクエスト単位で隔離** し、サーバー全体を停止しない
- Keychain エラーは `LocalizedError` で日本語メッセージを提供
:::
