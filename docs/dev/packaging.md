# パッケージング手順

AI KeyChain のビルドから **Developer ID 署名 + Apple 公証済み** DMG 配布までの手順。

::: tip 全自動スクリプト
以下の全手順は `scripts/build-release.sh` にまとまっています。前提条件を満たしていれば:

```bash
scripts/build-release.sh                # project.yml の MARKETING_VERSION でビルド
VERSION=1.8.0 scripts/build-release.sh  # バージョン明示
```

以降の節は各ステップの解説です。
:::

## 前提条件

- macOS 14+ (Sonoma)
- Swift 5.9+ / Xcode 15+
- `create-dmg` (`brew install create-dmg`)
- アプリアイコン PNG が `AIkeychain/Resources/Assets.xcassets/AppIcon.appiconset/` に配置済み
- **Developer ID Application 証明書**がログインキーチェーンにあること
  ```bash
  security find-identity -v -p codesigning
  # → "Developer ID Application: <NAME> (<TEAM_ID>)" が表示されること
  ```
  無い場合: Xcode → Settings → Accounts → チーム選択 → Manage Certificates → 「+」→ Developer ID Application（Account Holder 権限が必要）
- **notarytool のキーチェーンプロファイル**が登録済みであること（初回のみ）
  ```bash
  xcrun notarytool store-credentials AIKC_NOTARY \
    --apple-id <Apple ID> --team-id <TEAM_ID>
  ```
  App 用パスワードは https://account.apple.com → サインインとセキュリティ → App 用パスワード で生成し、
  **`--password` は付けずに実行して対話プロンプトで入力する**（argv に渡すとシェル履歴・`ps` に残る）。
  値は Keychain に保存され、ファイルには残らない。

## 手順

### 1. Release ビルド

```bash
swift build -c release
```

ビルド成果物: `.build/release/AIkeychain`

### 2. .app バンドル作成

```bash
# ディレクトリ構造を作成
APP_DIR="build/AI KeyChain.app/Contents"
mkdir -p "$APP_DIR/MacOS" "$APP_DIR/Resources"

# バイナリをコピー
cp .build/release/AIkeychain "$APP_DIR/MacOS/AI KeyChain"

# リソースバンドルをコピー (Assets.xcassets)
cp -R .build/release/AIkeychain_AIkeychain.bundle "$APP_DIR/Resources/"
```

### 3. Info.plist 作成

```bash
VERSION="1.1.0"  # CHANGELOG.md の最新バージョンに合わせる

cat > "$APP_DIR/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>AI KeyChain</string>
    <key>CFBundleDisplayName</key>
    <string>AI KeyChain</string>
    <key>CFBundleIdentifier</key>
    <string>com.aieo.aikeychain</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>AI KeyChain</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <false/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
</dict>
</plist>
PLIST
```

### 4. アプリアイコン (.icns) 生成

`swift build` は `.xcassets` をコンパイルしないため、`iconutil` で `.icns` を生成する。

```bash
SRC="AIkeychain/Resources/Assets.xcassets/AppIcon.appiconset"
ICONSET="/tmp/AppIcon.iconset"

rm -rf "$ICONSET" && mkdir -p "$ICONSET"
cp "$SRC/icon_16x16.png"     "$ICONSET/icon_16x16.png"
cp "$SRC/icon_32x32.png"     "$ICONSET/icon_16x16@2x.png"
cp "$SRC/icon_32x32.png"     "$ICONSET/icon_32x32.png"
cp "$SRC/icon_64x64.png"     "$ICONSET/icon_32x32@2x.png"
cp "$SRC/icon_128x128.png"   "$ICONSET/icon_128x128.png"
cp "$SRC/icon_256x256.png"   "$ICONSET/icon_128x128@2x.png"
cp "$SRC/icon_256x256.png"   "$ICONSET/icon_256x256.png"
cp "$SRC/icon_512x512.png"   "$ICONSET/icon_256x256@2x.png"
cp "$SRC/icon_512x512.png"   "$ICONSET/icon_512x512.png"
cp "$SRC/icon_1024x1024.png" "$ICONSET/icon_512x512@2x.png"

iconutil -c icns "$ICONSET" -o "$APP_DIR/Resources/AppIcon.icns"
```

### 5. Developer ID 署名（Hardened Runtime）

v1.8.0 以降の出荷物は **Developer ID Application 証明書 + Hardened Runtime** で署名する。
`--options runtime` は公証の必須条件であり、`DYLD_INSERT_LIBRARIES` による dylib 注入や
デコード済みシークレットを保持するプロセスへのデバッガアタッチへの防御にもなる（#114）。
**Proxy モードの outbound TLS 接続には network entitlements が必須。**

::: warning 正典レシピはローカルの `scripts/build-release.sh`
公証には Developer ID 証明書と notarytool クレデンシャルが必要なため、
**出荷 DMG はローカルで `scripts/build-release.sh` により生成する**。
CI（`.github/workflows/auto-release.yml`）は**リリースノートのみ**を作成し、
DMG は一切生成しない（未署名アーティファクトを「リリース」として公開しないため）。
CI への Developer ID 署名導入は #159 でトラッキング。
:::

::: danger リリースの順序（必須）
**公証済み DMG 付きの Release を発行してから、CHANGELOG を含む PR を main にマージする。**

1. リリースブランチで `scripts/build-release.sh` を実行
2. `gh release create vX.Y.Z --target <ブランチHEAD> ... build/AIKeyChain-vX.Y.Z.dmg build/AIKeyChain-vX.Y.Z.dmg.sha256`
3. PR をマージ（auto-release は既存 Release を検出してスキップ）

逆順でマージすると auto-release がノートのみの Release を先に作る。その場合は
`gh release upload vX.Y.Z build/AIKeyChain-vX.Y.Z.dmg{,.sha256}` で後から添付する。
:::

```bash
# network entitlements を作成
cat > build/aikeychain.entitlements << 'ENTITLEMENTS'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.network.server</key>
    <true/>
</dict>
</plist>
ENTITLEMENTS

# Developer ID + Hardened Runtime + secure timestamp で署名
codesign --force --options runtime --timestamp \
  --entitlements build/aikeychain.entitlements \
  --sign "Developer ID Application" \
  "build/AI KeyChain.app"

# 検証
codesign --verify --deep --strict "build/AI KeyChain.app"
```

::: warning entitlements なしの場合
`--entitlements` を省略すると Proxy モードの upstream TLS 接続がブロックされ、
API 呼び出しがタイムアウトします（Standard / Secret Reference モードは影響なし）。
:::

### 6. .app の公証 + staple

DMG から取り出した .app 単体でも（オフライン環境含め）Gatekeeper を通すため、
.app 自体を公証してチケットを staple する。

```bash
ditto -c -k --keepParent "build/AI KeyChain.app" "build/AI KeyChain.zip"
xcrun notarytool submit "build/AI KeyChain.zip" \
  --keychain-profile AIKC_NOTARY --wait
xcrun stapler staple "build/AI KeyChain.app"
rm "build/AI KeyChain.zip"
```

`--wait` は公証完了までブロックする（通常 1〜5 分）。ステータスが `Invalid` の場合は
`xcrun notarytool log <submission-id> --keychain-profile AIKC_NOTARY` で理由を確認する。

### 7. グラフィカル DMG 作成

`create-dmg` を使ってアプリアイコン + Applications ドラッグリンク付きのインストーラーを作成。

```bash
create-dmg \
  --volname "AI KeyChain" \
  --volicon "$APP_DIR/Resources/AppIcon.icns" \
  --window-pos 200 120 \
  --window-size 660 400 \
  --icon-size 120 \
  --icon "AI KeyChain.app" 160 185 \
  --hide-extension "AI KeyChain.app" \
  --app-drop-link 500 185 \
  --no-internet-enable \
  "build/AIKeyChain-v${VERSION}.dmg" \
  "build/AI KeyChain.app"
```

::: tip create-dmg のインストール
```bash
brew install create-dmg
```
:::

### 8. DMG の署名 + 公証 + staple

```bash
codesign --force --timestamp --sign "Developer ID Application" \
  "build/AIKeyChain-v${VERSION}.dmg"

xcrun notarytool submit "build/AIKeyChain-v${VERSION}.dmg" \
  --keychain-profile AIKC_NOTARY --wait
xcrun stapler staple "build/AIKeyChain-v${VERSION}.dmg"
```

### 9. 検証とチェックサム

```bash
# Gatekeeper 通過を確認（"accepted" / "Notarized Developer ID" が出ること）
spctl --assess --type execute -vv "build/AI KeyChain.app"
spctl --assess --type open --context context:primary-signature -vv \
  "build/AIKeyChain-v${VERSION}.dmg"
xcrun stapler validate "build/AIKeyChain-v${VERSION}.dmg"

# リリースに添付する SHA-256 チェックサム
shasum -a 256 "build/AIKeyChain-v${VERSION}.dmg" \
  | tee "build/AIKeyChain-v${VERSION}.dmg.sha256"
```

::: warning リリースごとの実機起動テスト（必須）
`spctl` は Gatekeeper 判定しか見ない。**リリースごとに生成 DMG からアプリを実際に
インストール・起動し、主要機能（キー一覧表示・Proxy モードの upstream TLS 接続）を
確認すること**。Hardened Runtime + entitlements の組み合わせ不備は起動時にしか
発現しない。
:::

### 10. インストール

```bash
# DMG を開く → AI KeyChain.app を Applications にドラッグ
open build/AIKeyChain-v${VERSION}.dmg
```

公証 + staple 済みのため、quarantine 属性の手動削除（`xattr`）は**不要**。

## ワンライナー (全手順)

**`scripts/build-release.sh` を使うこと**（上記手順 1〜9 を全自動化、公証込み）。

<details>
<summary>旧・ad-hoc 署名ワンライナー（Developer ID 証明書がない環境向け、参考）</summary>

```bash
VERSION="1.1.0" && \
swift build -c release && \
APP="build/AI KeyChain.app/Contents" && \
rm -rf build && mkdir -p "$APP/MacOS" "$APP/Resources" && \
cp .build/release/AIkeychain "$APP/MacOS/AI KeyChain" && \
cp -R .build/release/AIkeychain_AIkeychain.bundle "$APP/Resources/" && \
cat > "$APP/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>AI KeyChain</string>
    <key>CFBundleDisplayName</key><string>AI KeyChain</string>
    <key>CFBundleIdentifier</key><string>com.aieo.aikeychain</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>AI KeyChain</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><false/>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
</dict>
</plist>
PLIST
SRC="AIkeychain/Resources/Assets.xcassets/AppIcon.appiconset" && \
ICONSET="/tmp/AppIcon.iconset" && rm -rf "$ICONSET" && mkdir "$ICONSET" && \
cp "$SRC/icon_16x16.png" "$ICONSET/icon_16x16.png" && \
cp "$SRC/icon_32x32.png" "$ICONSET/icon_16x16@2x.png" && \
cp "$SRC/icon_32x32.png" "$ICONSET/icon_32x32.png" && \
cp "$SRC/icon_64x64.png" "$ICONSET/icon_32x32@2x.png" && \
cp "$SRC/icon_128x128.png" "$ICONSET/icon_128x128.png" && \
cp "$SRC/icon_256x256.png" "$ICONSET/icon_128x128@2x.png" && \
cp "$SRC/icon_256x256.png" "$ICONSET/icon_256x256.png" && \
cp "$SRC/icon_512x512.png" "$ICONSET/icon_256x256@2x.png" && \
cp "$SRC/icon_512x512.png" "$ICONSET/icon_512x512.png" && \
cp "$SRC/icon_1024x1024.png" "$ICONSET/icon_512x512@2x.png" && \
iconutil -c icns "$ICONSET" -o "$APP/Resources/AppIcon.icns" && \
codesign --force --deep --options runtime --sign - "build/AI KeyChain.app" && \
create-dmg \
  --volname "AI KeyChain" \
  --volicon "$APP/Resources/AppIcon.icns" \
  --window-pos 200 120 \
  --window-size 660 400 \
  --icon-size 120 \
  --icon "AI KeyChain.app" 160 185 \
  --hide-extension "AI KeyChain.app" \
  --app-drop-link 500 185 \
  --no-internet-enable \
  "build/AIKeyChain-v${VERSION}.dmg" \
  "build/AI KeyChain.app" && \
echo "Done: build/AIKeyChain-v${VERSION}.dmg"
```

</details>

## トラブルシューティング

| 問題 | 解決策 |
|------|--------|
| 型推論エラー (`unable to type-check`) | 複雑な SwiftUI ビューを `@ViewBuilder` プロパティに分割 |
| アプリアイコンが表示されない | `.icns` が `Resources/` にあるか確認。`swift build` は xcassets をコンパイルしない |
| DMG がフォルダ表示になる | `hdiutil` ではなく `create-dmg` を使う |
| 「壊れているため開けません」「信頼されていない開発元」 | v1.8.0 以降の公証済み DMG では発生しない。表示されたら旧ビルドの可能性 — 最新リリースを取り直す。ローカルの ad-hoc ビルド検証時のみ `xattr -cr`（`sudo` 不要） |
| `codesign` が identity を見つけられない | `security find-identity -v -p codesigning` で Developer ID 証明書の有無を確認（前提条件参照） |
| 公証が `Invalid` になる | `xcrun notarytool log <submission-id> --keychain-profile AIKC_NOTARY` で原因確認。Hardened Runtime（`--options runtime`）と secure timestamp（`--timestamp`）の欠落が典型 |
| `create-dmg` が見つからない | `brew install create-dmg` |
