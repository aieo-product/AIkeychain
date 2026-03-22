# 設計書 概要

AI KeyChain の設計ドキュメント一覧です。

## ドキュメント構成

| ドキュメント | 概要 |
|------------|------|
| [アーキテクチャ](./architecture) | レイヤー構成・データフロー・ファイル構成 |
| [データモデル](./data-model) | ServiceType / KeyCategory / APIKey の定義 |
| [UI/UXデザイン](./ui-ux) | 画面設計・フロー・カラーパレット |
| [セキュリティ](./security) | 脅威モデル・対策・比較表 |

## 技術スタック

| 要素 | 選定 |
|------|------|
| UI | SwiftUI (macOS 14+) |
| 状態管理 | @Observable (Observation framework) |
| Keychain | Security.framework 直接利用 |
| 最小OS | macOS 14 Sonoma |
| Xcode | 15+ |
| 言語 | Swift 5.9+ |
