# アーキテクチャ設計

> GitHub Issue: [#1 アプリケーションアーキテクチャ設計書](https://github.com/aieo-product/AIkeychain/issues/1)

## レイヤー構成

```
┌─────────────────────────────────────────────────┐
│                  Presentation Layer              │
│  ┌───────────┐ ┌───────────┐ ┌───────────────┐  │
│  │Onboarding │ │ Main View │ │ Export View   │  │
│  │  Views    │ │  (CRUD)   │ │ (.zshrc/.env) │  │
│  └─────┬─────┘ └─────┬─────┘ └──────┬────────┘  │
├────────┼─────────────┼───────────────┼──────────┤
│        └─────────────┼───────────────┘           │
│                  ViewModel Layer                  │
│  ┌───────────────────┴───────────────────────┐   │
│  │   @Observable ViewModels                  │   │
│  │   (OnboardingVM / KeyListVM / EditorVM)   │   │
│  └───────────────────┬───────────────────────┘   │
├──────────────────────┼──────────────────────────┤
│                 Service Layer                    │
│  ┌──────────────┐  ┌──────────────────────┐     │
│  │ Keychain     │  │ ZshrcExporter        │     │
│  │ Service      │  │ (export文生成)       │     │
│  └──────┬───────┘  └──────────────────────┘     │
├─────────┼───────────────────────────────────────┤
│         ▼          System Layer                  │
│  ┌──────────────────────────────────────────┐   │
│  │      macOS Keychain (Security.framework) │   │
│  └──────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
```

## データフロー

```
User Input
    │
    ▼
┌──────────┐    save     ┌──────────────┐    SecItemAdd    ┌─────────┐
│ SwiftUI  │ ──────────▶ │ KeychainSvc  │ ──────────────▶  │Keychain │
│  View    │             │  (Service)   │                  │  (OS)   │
│          │ ◀────────── │              │ ◀────────────── │         │
└──────────┘   Result    └──────────────┘   SecItemCopy    └─────────┘
```

## ファイル構成

```
AIkeychain/
├── AIKeychainApp.swift              # エントリポイント
├── Info.plist
├── AIkeychain.entitlements          # Keychain Access
│
├── Models/
│   ├── APIKey.swift                 # キー情報のデータモデル
│   ├── KeyCategory.swift            # カテゴリ定義 (enum)
│   ├── ServiceType.swift            # サービス種別定義 (enum)
│   └── OnboardingStep.swift         # オンボーディングステップ定義
│
├── Services/
│   ├── KeychainService.swift        # Keychain CRUD ヘルパー
│   └── ZshrcExporter.swift          # .zshrc export文生成
│
├── ViewModels/
│   ├── OnboardingViewModel.swift    # オンボーディングフロー制御
│   ├── KeyListViewModel.swift       # メイン画面のキー一覧管理
│   └── KeyEditorViewModel.swift     # キー追加・編集のバリデーション
│
├── Views/
│   ├── ContentView.swift            # ルートビュー (ルーティング)
│   ├── Onboarding/
│   │   ├── OnboardingContainerView.swift
│   │   ├── WelcomeStepView.swift
│   │   ├── GitHubTokenStepView.swift
│   │   ├── AIKeysStepView.swift
│   │   ├── OptionalKeysStepView.swift
│   │   └── CompletionStepView.swift
│   ├── Main/
│   │   ├── MainView.swift
│   │   ├── SidebarView.swift
│   │   ├── KeyListView.swift
│   │   └── KeyRowView.swift
│   ├── Editor/
│   │   └── KeyEditorView.swift
│   └── Export/
│       └── ZshrcExportView.swift
│
├── Components/
│   ├── StatusBadge.swift
│   ├── CategoryIcon.swift
│   ├── SecureFieldToggle.swift
│   └── GradientCard.swift
│
├── Theme/
│   ├── AppColors.swift
│   ├── AppFonts.swift
│   └── AppAnimations.swift
│
└── Resources/
    └── Assets.xcassets/
```

## 状態管理方針

macOS 14+ の **Observation framework** (`@Observable`) を採用。

```swift
@Observable
class KeyListViewModel {
    var keys: [APIKey] = []
    var selectedCategory: KeyCategory?

    private let keychainService: KeychainServiceProtocol

    func loadKeys() {
        // Keychain から各サービスの存在チェック
    }
}
```

::: tip なぜ @Observable？
- `ObservableObject` + `@Published` よりパフォーマンスが良い
- ボイラープレートが少ない
- SwiftUI との統合がよりシンプル
:::

## エラーハンドリング方針

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
