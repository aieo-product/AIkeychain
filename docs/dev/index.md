# 開発セットアップ

## 必要環境

| 要素 | バージョン |
|------|-----------|
| macOS | 14 Sonoma+ |
| Xcode | 15+ |
| Swift | 5.9+ |
| Node.js | 18+ (ドキュメントビルド用) |

## リポジトリのクローン

```bash
git clone git@github.com:aieo-product/AIkeychain.git
cd AIkeychain
```

## ドキュメントサイトの開発

```bash
npm install
npm run docs:dev
```

## Xcode プロジェクト

```bash
open AIkeychain.xcodeproj
```

::: info
Xcode プロジェクトは [Issue #4](https://github.com/aieo-product/AIkeychain/issues/4) で作成予定です。
:::

## ブランチ戦略

| ブランチ | 用途 |
|---------|------|
| `main` | リリースブランチ |
| `feature/xxx` | 機能開発 |
| `fix/xxx` | バグ修正 |
| `docs/xxx` | ドキュメント |
