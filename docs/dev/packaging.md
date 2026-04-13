# パッケージング手順

AI KeyChain のビルドからグラフィカル DMG 配布までの手順。

## 前提条件

- macOS 14+ (Sonoma)
- Swift 5.9+ / Xcode 15+
- `create-dmg` (`brew install create-dmg`)
- アプリアイコン PNG が `AIkeychain/Resources/Assets.xcassets/AppIcon.appiconset/` に配置済み

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

### 5. Ad-hoc コード署名

Developer ID がない場合の署名（「壊れているため開けません」エラーを防止）。
**Proxy モードの outbound TLS 接続には network entitlements が必須。**

```bash
# network entitlements を作成（初回のみ）
cat > /tmp/aikeychain.entitlements << 'ENTITLEMENTS'
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

# entitlements 付きで署名
codesign --force --deep --sign - \
  --entitlements /tmp/aikeychain.entitlements \
  "build/AI KeyChain.app"
```

::: warning entitlements なしの場合
`--entitlements` を省略すると Proxy モードの upstream TLS 接続がブロックされ、
API 呼び出しがタイムアウトします（Standard / Secret Reference モードは影響なし）。
:::

### 6. グラフィカル DMG 作成

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

### 7. インストール

```bash
# DMG を開く
open build/AIKeyChain-v${VERSION}.dmg

# AI KeyChain.app を Applications にドラッグ

# Gatekeeper の検疫属性を削除 (署名なしの場合)
xattr -cr /Applications/AI\ KeyChain.app
```

## ワンライナー (全手順)

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
codesign --force --deep --sign - "build/AI KeyChain.app" && \
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

## トラブルシューティング

| 問題 | 解決策 |
|------|--------|
| 型推論エラー (`unable to type-check`) | 複雑な SwiftUI ビューを `@ViewBuilder` プロパティに分割 |
| アプリアイコンが表示されない | `.icns` が `Resources/` にあるか確認。`swift build` は xcassets をコンパイルしない |
| DMG がフォルダ表示になる | `hdiutil` ではなく `create-dmg` を使う |
| 「壊れているため開けません」 | `xattr -cr /Applications/AI\ KeyChain.app` を実行 |
| 「信頼されていない開発元」 | システム設定 → プライバシーとセキュリティ → 「このまま開く」 |
| `create-dmg` が見つからない | `brew install create-dmg` |
