# UI/UX デザイン

> GitHub Issue: [#3 UI/UXデザイン](https://github.com/aieo-product/AIkeychain/issues/3)

## 画面一覧

| 画面 | 種別 | 説明 |
|------|------|------|
| WelcomeStep | Onboarding | アプリ紹介 |
| GitHubTokenStep | Onboarding | GitHub トークン設定 (必須) |
| AIKeysStep | Onboarding | AI API キー設定 (推奨) |
| OtherKeysStep | Onboarding | その他キー設定 (任意) |
| CompletionStep | Onboarding | セットアップ完了 |
| MainView | Main | キー一覧 (NavigationSplitView) |
| KeyEditorView | Sheet | キー追加・編集 |
| ZshrcExportView | Sheet | Export プレビュー |

## オンボーディングフロー

![Onboarding Flow](/assets/diagrams/onboarding-flow.svg)

## メイン画面

![Main Screen](/assets/diagrams/main-screen.svg)

## キー編集シート

| 要素 | 内容 |
|------|------|
| ヘッダー | サービス名 + アイコン |
| 環境変数名 | 自動入力 (編集可能) |
| トークン入力 | SecureField + 表示/非表示トグル |
| バリデーション | プレフィックスチェック結果表示 |
| リンク | トークン発行ページを開く |
| アクション | キャンセル / Keychainに保存 |

## カラーパレット

### カテゴリカラー

| カテゴリ | カラー | Hex |
|---------|--------|-----|
| AI API | :purple_circle: Purple | `#7C3AED` |
| Code & Git | :orange_circle: Orange | `#EA580C` |
| Cloud | :blue_circle: Blue | `#0284C7` |
| Communication | :green_circle: Green | `#059669` |
| DevTools | :white_circle: Gray | `#6B7280` |

### ステータスカラー

| ステータス | カラー | Hex |
|-----------|--------|-----|
| 設定済み | :green_circle: Emerald | `#10B981` |
| 未設定 | :yellow_circle: Amber | `#F59E0B` |

### アクセントグラデーション

```
#7C3AED (Purple) → #0284C7 (Blue) → #059669 (Green)
```

## タイポグラフィ

| 用途 | フォント | サイズ |
|------|---------|--------|
| ページタイトル | System Bold | 28pt |
| セクションタイトル | System Semibold | 20pt |
| 本文 | System Regular | 14pt |
| コード・トークン | SF Mono | 13pt |
| バッジ | System Medium | 11pt |

## アニメーション仕様

| 対象 | 種類 | 時間 |
|------|------|------|
| オンボーディング遷移 | slide + fade | 0.3s (spring) |
| ステータスバッジ変化 | scale + color | 0.2s (easeInOut) |
| シート表示 | system default | - |
| 保存成功フィードバック | checkmark scale | 0.5s (spring bounce) |
