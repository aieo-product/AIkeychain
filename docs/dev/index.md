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

`project.yml` から XcodeGen でプロジェクトを生成する構成。

```bash
xcodegen generate
open AIkeychain.xcodeproj
```

## Swift Package Manager によるビルド

```bash
swift build -c release
```

## `akc` CLI (Secret Reference 解決)

`scripts/akc` が `keychain://KEY_NAME` 形式の環境変数を実行時に解決する Bash スクリプト。
Secret Reference モードで利用する。

```bash
# 解決対象を確認 (値はマスク)
./scripts/akc run --dry-run

# コマンドを実行
./scripts/akc run -- claude
```

PATH に通すには `~/.local/bin` などにコピー / シンボリックリンクを作成する。

## ブランチ戦略

| ブランチ | 用途 |
|---------|------|
| `main` | リリースブランチ |
| `feature/xxx` | 機能開発 |
| `fix/xxx` | バグ修正 |
| `docs/xxx` | ドキュメント |
| `test/xxx` | テスト・検証 |
