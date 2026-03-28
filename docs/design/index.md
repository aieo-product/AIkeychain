# 設計書 概要

AI KeyChain の設計ドキュメント一覧です。

## ドキュメント構成

| ドキュメント | 概要 |
|------------|------|
| [アーキテクチャ](./architecture) | レイヤー構成・データフロー・ファイル構成・状態管理・エラーハンドリング |
| [データモデル](./data-model) | ServiceType / KeyCategory / APIKey / CustomKeyStore / ProxyRoute |
| [UI/UXデザイン](./ui-ux) | 画面設計・フロー・カラーパレット・メニューバー |
| [セキュリティ](./security) | 脅威モデル・Proxy セキュリティ・暗号化キー転送・Entitlements |

## 技術スタック

| 要素 | 選定 |
|------|------|
| UI | SwiftUI (macOS 14+) |
| 状態管理 | @Observable (Observation framework) |
| Keychain | Security.framework 直接利用 |
| プロキシ | Network.framework (NWListener) |
| 暗号化 | CryptoKit (P-256 ECDH + AES-256-GCM) |
| ログイン起動 | ServiceManagement (SMAppService) |
| 最小 OS | macOS 14 Sonoma |
| Xcode | 15+ |
| 言語 | Swift 5.9+ |

## アーキテクチャ概要

```mermaid
graph LR
    User["ユーザー"] --> |Standard| Shell[".zshrc<br/>security コマンド"]
    User --> |Proxy| App["AI KeyChain<br/>ProxyServer"]
    Shell --> Keychain["macOS<br/>Keychain"]
    App --> Keychain
    App --> |HTTPS + 認証ヘッダー| API["AI API<br/>(Anthropic, OpenAI, xAI)"]
    Shell --> |環境変数| Code["開発コード"]
    Code --> API

    style Keychain fill:#FEF3C7,stroke:#F59E0B
    style App fill:#D1FAE5,stroke:#059669
```

### デュアルモード設計

| モード | 仕組み | セキュリティ | 要件 |
|--------|--------|------------|------|
| **Standard** | .zshrc から `security` コマンドで Keychain 参照 | 環境変数に値が露出 | アプリ常駐不要 |
| **Proxy** | localhost HTTP プロキシが認証ヘッダーを注入 | 環境変数に値が露出しない | アプリ常駐必要 |
