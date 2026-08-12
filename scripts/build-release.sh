#!/bin/bash
# AI KeyChain — Developer ID 署名 + 公証済み DMG ビルドスクリプト
#
# 前提:
#   - Developer ID Application 証明書がログインキーチェーンにあること
#     (security find-identity -v -p codesigning で確認)
#   - notarytool のキーチェーンプロファイルが登録済みであること
#     (xcrun notarytool store-credentials <profile> --apple-id ... --team-id ... --password <app用パスワード>)
#   - create-dmg (brew install create-dmg)
#
# 使い方:
#   scripts/build-release.sh                    # project.yml の MARKETING_VERSION を使用
#   VERSION=1.8.0 scripts/build-release.sh      # バージョン明示
#   SIGN_IDENTITY / NOTARY_PROFILE も環境変数で上書き可
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${VERSION:-$(sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml)}"
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application}"
NOTARY_PROFILE="${NOTARY_PROFILE:-AIKC_NOTARY}"

APP_NAME="AI KeyChain"
APP="build/${APP_NAME}.app"
CONTENTS="$APP/Contents"
DMG="build/AIKeyChain-v${VERSION}.dmg"

echo "==> Version: $VERSION / Identity: $SIGN_IDENTITY / Profile: $NOTARY_PROFILE"

# 1. Release ビルド
swift build -c release

# 2. .app バンドル作成
rm -rf build && mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp .build/release/AIkeychain "$CONTENTS/MacOS/$APP_NAME"
cp -R .build/release/AIkeychain_AIkeychain.bundle "$CONTENTS/Resources/"

# 3. Info.plist
cat > "$CONTENTS/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>com.aieo.aikeychain</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><false/>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
</dict>
</plist>
PLIST

# 4. アプリアイコン (.icns) — swift build は xcassets をコンパイルしない
SRC="AIkeychain/Resources/Assets.xcassets/AppIcon.appiconset"
ICONSET="build/AppIcon.iconset"
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
iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/AppIcon.icns"

# 5. Developer ID 署名 (Hardened Runtime + timestamp)
#    network entitlements は Proxy モードの outbound TLS / ローカル listener に必須
cat > build/aikeychain.entitlements << 'ENTITLEMENTS'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.network.client</key><true/>
    <key>com.apple.security.network.server</key><true/>
</dict>
</plist>
ENTITLEMENTS

codesign --force --options runtime --timestamp \
  --entitlements build/aikeychain.entitlements \
  --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"

# 6. .app を公証 → staple(DMG から取り出した後もオフラインで Gatekeeper を通すため)
ditto -c -k --keepParent "$APP" "build/${APP_NAME}.zip"
xcrun notarytool submit "build/${APP_NAME}.zip" \
  --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
rm "build/${APP_NAME}.zip"

# 7. グラフィカル DMG 作成 → 署名 → 公証 → staple
create-dmg \
  --volname "$APP_NAME" \
  --volicon "$CONTENTS/Resources/AppIcon.icns" \
  --window-pos 200 120 \
  --window-size 660 400 \
  --icon-size 120 \
  --icon "${APP_NAME}.app" 160 185 \
  --hide-extension "${APP_NAME}.app" \
  --app-drop-link 500 185 \
  --no-internet-enable \
  "$DMG" "$APP"

codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"

# 8. 検証
echo "==> Gatekeeper assessment"
spctl --assess --type execute -vv "$APP"
spctl --assess --type open --context context:primary-signature -vv "$DMG"
xcrun stapler validate "$DMG"

# 9. チェックサム公開用
shasum -a 256 "$DMG" | tee "${DMG}.sha256"

echo "Done: $DMG"
