---
outline: [2, 3]
---

# 試験結果

AI KeyChain の動作確認テスト結果を掲載しています。

## v1.6.1 セキュリティ強化 総合確認 (最新)

- [試験仕様書・結果](/test/v1.6.1)
- GitHub Issue: 監査対応 [#112](https://github.com/aieo-product/AIkeychain/issues/112)〜[#134](https://github.com/aieo-product/AIkeychain/issues/134)、本試験発見 [#135](https://github.com/aieo-product/AIkeychain/issues/135)

| 項目 | 内容 |
|------|------|
| 試験日 | 2026-07-06 |
| Swift ユニット | 139 / 139 PASS |
| CLI ユニット/統合 | 60 / 60 PASS |
| CLI コマンド | 9 項目 PASS |
| 自然言語 / MCP 参照 | 6 項目 PASS |
| GUI エビデンス | 7 画面 |
| 判定 | **ALL PASS**（発見1件は同PRで修正、1件は #135 follow-up） |

### 実施内容
- CLI / 自然言語（MCP）/ GUI の 3 系統で秘密値の非露出導線を実機検証
- 監査対応（送信者認証・トークン権限・PATH 固定・マスク・キー名検証・MCP 絶対パス化）の動作確認
- 発見: Node CLI マスク桁数漏洩を修正、My Keys 指紋表示を #135 起票

## v1.6.0 最終リリース確認

- [試験仕様書・結果](/test/v1.6.0-final)
- GitHub Issue: [#64](https://github.com/aieo-product/AIkeychain/issues/64), [#84](https://github.com/aieo-product/AIkeychain/issues/84)

| 項目 | 内容 |
|------|------|
| 試験日 | 2026-04-14 〜 2026-04-20 |
| UI 試験 | 14 件 全 PASS |
| Proxy 試験 | 7 件 全 PASS（200 OK × 3 含む） |
| Xcode ユニットテスト | 67 / 67 PASS |
| 判定 | **ALL PASS** |

### 実施内容
- UI キャプチャ 14 枚 (個人情報マスク済み)
- Proxy 正常系・異常系 網羅試験 (200 OK / 403 / 502 / 400)
- Activity ログ修正 (#84) 前後のエビデンス比較
- Codex コードレビュー (正常系 + 異常系)

## v1.6.0 初期試験

- [試験仕様書・結果](/test/v1.6.0)
- GitHub Issue: [#72](https://github.com/aieo-product/AIkeychain/issues/72)

| 項目 | 内容 |
|------|------|
| 試験日 | 2026-04-13 |
| 総テスト数 | 26 件 |
| 合格 | 26 件 |
| 不合格 | 0 件 |
| 判定 | **ALL PASS** |

### v1.6.0 新規テスト項目
- Secret Reference モード (akc CLI) — 5 件
- i18n 英語対応 — 6 件
- UI/UX (モード選択スクロール、Add Key 修正) — 6 件

## v1.5.1

- [試験仕様書・結果](/test/v1.5.1)
- GitHub Issue: [#28](https://github.com/aieo-product/AIkeychain/issues/28), [#23](https://github.com/aieo-product/AIkeychain/issues/23)

| 項目 | 内容 |
|------|------|
| 試験日 | 2026-03-30 |
| 総テスト数 | 64 件 |
| 合格 | 64 件 |
| 不合格 | 0 件 |
| 判定 | **ALL PASS** |

## v1.0.0

- [試験仕様書・結果](/test/v1.0.0)
- GitHub Issue: [#28](https://github.com/aieo-product/AIkeychain/issues/28)

| 項目 | 内容 |
|------|------|
| 試験日 | 2026-03-24 |
| 総テスト数 | 66 件 |
| 合格 | 66 件 |
| 不合格 | 0 件 |
| 判定 | **ALL PASS** |
