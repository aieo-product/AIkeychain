# セキュリティ設計

> GitHub Issue: [#15 セキュリティ設計書](https://github.com/aieo-product/AIkeychain/issues/15)

## 脅威モデル

```
┌──────────────────────────────────────────────────────────────┐
│                    Threat Model                              │
│                                                              │
│  ┌──────────────┐                                           │
│  │  Attacker    │                                           │
│  └──────┬───────┘                                           │
│         │                                                    │
│    ┌────┴────┐────────┐────────┐────────┐                   │
│    ▼         ▼        ▼        ▼        ▼                   │
│ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐              │
│ │.env  │ │Clip  │ │Memory│ │Backup│ │Git   │              │
│ │平文  │ │board │ │Dump  │ │漏洩  │ │誤commit│             │
│ └──┬───┘ └──┬───┘ └──┬───┘ └──┬───┘ └──┬───┘              │
│    │        │        │        │        │                    │
│    ▼        ▼        ▼        ▼        ▼                   │
│ ┌──────────────────────────────────────────────────┐        │
│ │              AI KeyChain の対策                   │        │
│ ├──────────────────────────────────────────────────┤        │
│ │ ✅ Keychain暗号化    (平文ファイル不要)          │        │
│ │ ✅ Clipboard自動クリア (30秒)                    │        │
│ │ ✅ SecureField使用    (メモリ最小保持)           │        │
│ │ ✅ .gitignore推奨     (誤commit防止)             │        │
│ │ ✅ App Sandbox        (プロセス分離)             │        │
│ └──────────────────────────────────────────────────┘        │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

## 保管方法の比較

| 保管方法 | 安全性 | 利便性 | 推奨度 |
|---------|--------|--------|--------|
| .env 平文ファイル | :star: | :star::star::star::star::star: | :x: |
| .zshrc 直書き | :star: | :star::star::star::star::star: | :x: |
| 環境変数 (export) | :star::star: | :star::star::star::star: | :warning: |
| **macOS Keychain** | **:star::star::star::star:** | **:star::star::star:** | **:white_check_mark: 本アプリ** |
| Secure Enclave | :star::star::star::star::star: | :star::star: | (SSH鍵向け) |
| Hardware Key | :star::star::star::star::star: | :star: | (認証向け) |

## Keychain アクセス制御

### kSecAttrAccessible の選定

```
kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
```

| 属性 | 意味 |
|------|------|
| AfterFirstUnlock | ユーザーが1回ロック解除した後はアクセス可能 |
| ThisDeviceOnly | iCloud Keychain で同期しない (セキュリティ優先) |

::: tip なぜこの設定？
- `WhenUnlocked` だとスリープ復帰ごとにアクセス不可になり利便性が下がる
- `AfterFirstUnlock` は起動後1回のロック解除で以降アクセス可能
- `ThisDeviceOnly` でデバイス間の漏洩リスクを排除
:::

### Keychain クエリ構成

```swift
let query: [String: Any] = [
    kSecClass as String:            kSecClassGenericPassword,
    kSecAttrService as String:      "com.aieo.aikeychain",
    kSecAttrAccount as String:      envVarName,     // "ANTHROPIC_API_KEY"
    kSecValueData as String:        tokenData,       // UTF-8 encoded
    kSecAttrAccessible as String:   kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
]
```

## クリップボード自動クリア

トークン値をクリップボードにコピーした場合、**30秒後に自動クリア**する。

```swift
func copyToClipboard(_ value: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)

    // 30秒後にクリア
    DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
        NSPasteboard.general.clearContents()
    }
}
```

## App Sandbox 設定

```xml
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>keychain-access-groups</key>
    <array>
        <string>$(AppIdentifierPrefix)com.aieo.aikeychain</string>
    </array>
    <key>com.apple.security.network.client</key>
    <true/>   <!-- トークン発行ページを開くため -->
</dict>
```

## トークンバリデーション

入力されたトークンのプレフィックスをチェックし、誤入力を防止する。

| Service | Expected Prefix | Example |
|---------|----------------|---------|
| Anthropic | `sk-ant-` | `sk-ant-api03-xxxxx` |
| OpenAI | `sk-` | `sk-xxxxx` |
| GitHub | `ghp_` or `gho_` | `ghp_xxxxx` |
| GitLab | `glpat-` | `glpat-xxxxx` |
| xAI | `xai-` | `xai-xxxxx` |
| Tailscale | `tskey-` | `tskey-client-xxxxx` |
| Slack | `xapp-` or `xoxb-` | `xapp-1-xxxxx` |

::: warning 注意
プレフィックスチェックは**警告のみ**で、保存をブロックはしない。
サービス側がプレフィックス形式を変更する可能性があるため。
:::

## セキュリティチェックリスト

- [ ] Keychain にのみシークレットを保存 (ファイル書き出しなし)
- [ ] SecureField で入力中のマスキング
- [ ] メモリ上でのトークン保持を最小化
- [ ] クリップボード30秒自動クリア
- [ ] App Sandbox 有効
- [ ] ThisDeviceOnly でiCloud同期無効
- [ ] .gitignore に .env 等を推奨記載
- [ ] Export時の平文警告表示
