import Foundation

/// アプリ内ローカライズヘルパー
/// 使用例: L10n.t("welcome_title")
enum L10n {
    /// 現在の言語で文字列を返す
    static func t(_ key: String) -> String {
        let lang = AppState.shared.appLanguage
        let table = lang == .ja ? ja : en
        return table[key] ?? key
    }

    /// 日本語/英語を直接指定して返す
    static func s(ja jaText: String, en enText: String) -> String {
        AppState.shared.appLanguage == .ja ? jaText : enText
    }

    /// 現在の言語が日本語か
    static var isJa: Bool {
        AppState.shared.appLanguage == .ja
    }

    // MARK: - Common

    private static let ja: [String: String] = [
        // Navigation
        "back": "戻る",
        "next": "次へ",
        "skip": "スキップ",
        "cancel": "キャンセル",
        "done": "完了",
        "apply": "適用",
        "save": "保存",
        "delete": "削除",
        "copy": "コピー",

        // Onboarding - Language
        "language_title": "言語を選択",
        "language_subtitle": "アプリ内の表示言語を選択してください。\nあとからいつでも変更できます。",

        // Onboarding - Welcome
        "welcome_title": "AI KeyChain",
        "welcome_subtitle": "AI API キーをセキュアに管理する macOS アプリ",
        "welcome_feature1_title": "Keychain で安全に保管",
        "welcome_feature1_desc": "API キーは macOS Keychain に暗号化保存",
        "welcome_feature2_title": "環境変数に露出しない",
        "welcome_feature2_desc": "AI が env コマンドで見てもキーは表示されない",
        "welcome_feature3_title": "ローカルプロキシで自動注入",
        "welcome_feature3_desc": "認証ヘッダをバックグラウンドで安全に追加",

        // Onboarding - Mode Select
        "mode_select_title": "モードを選択",
        "mode_select_subtitle": "API キーの管理方式を選んでください。\nあとからいつでも変更できます。",
        "mode_standard_subtitle": "安定・シンプル",
        "mode_standard_pro": "設定がシンプル",
        "mode_standard_con": "env にキーが見える",
        "mode_secretref_subtitle": "1Password 方式",
        "mode_secretref_pro": "env にキー値が出ない",
        "mode_secretref_con": "akc run が必要",
        "mode_proxy_subtitle": "最も安全",
        "mode_proxy_pro": "キーが完全に隠蔽",
        "mode_proxy_con": "アプリ常時起動",
        "mode_proxy_warning": "Proxy モードはアプリ常時起動が前提です。停止時の復旧方法はアプリ内で確認できます。",
        "mode_secretref_info": "akc run -- <command> でラップして実行すると、keychain:// が自動解決されます。",

        // Onboarding - Flow Diagram
        "flow_terminal": "Terminal / AI ツール",
        "flow_api_server": "API Server",
        "flow_standard_detail": "export API_KEY=$(security ...)",
        "flow_standard_arrow": "API キーを直接送信",
        "flow_secretref_detail": "env: keychain://API_KEY",
        "flow_secretref_arrow1": "akc run が Keychain から解決",
        "flow_secretref_child": "子プロセス",
        "flow_secretref_child_detail": "実際のキー値を env に注入",
        "flow_secretref_arrow2": "API キーを送信",
        "flow_proxy_detail": "env にキーなし",
        "flow_proxy_arrow1": "認証なしリクエスト",
        "flow_proxy_box": "AI KeyChain Proxy",
        "flow_proxy_box_detail": "Keychain → ヘッダ注入",
        "flow_proxy_arrow2": "認証済みリクエスト",

        // Onboarding - Register Keys
        "register_title": "キーを登録",
        "register_subtitle": "管理したい API キーを登録しましょう。\nあとからメイン画面でいつでも追加・編集できます。",
        "register_tip": "Tip: メイン画面でキーをダブルクリック or 右クリック → Edit",

        // Onboarding - Shell Setup
        "shell_title": "シェルを接続",
        "shell_subtitle": ".zshrc に1行追加するだけで、プロキシ起動中のみ\nBASE_URL が自動設定されます。",
        "shell_port": "Port:",
        "shell_default_port": "(デフォルト: %@)",
        "shell_zshrc_label": "~/.zshrc に追記される内容:",
        "shell_note1": "プロキシ起動中のみ ~/.aikeychain_proxy が存在します",
        "shell_note2": "プロキシ停止時はファイルが自動削除されます",
        "shell_note3": "BASE_URL が残り続ける問題は発生しません",
        "shell_configured": "設定済み",
        "shell_enable_proxy": "Secure Proxy を有効化",
        "shell_key_safe": "API キーの値は書き込まれません。安全です。",
        "shell_port_error": "ポート番号は 1024〜65535 の範囲で指定してください",

        // Onboarding - Completion
        "completion_title": "セットアップ完了！",
        "get_started": "はじめる",
        "completion_standard": "Standard モードでセットアップ完了",
        "completion_secretref": "Secret Reference モードでセットアップ完了",
        "completion_proxy": "Proxy モードでセットアップ完了",
        "completion_standard_step1": "API キーを Keychain に登録",
        "completion_standard_step2": ".zshrc の export で環境変数に設定",
        "completion_standard_step3": "ターミナルで AI ツールをそのまま使う",
        "completion_secretref_step1": "API キーを Keychain に登録",
        "completion_secretref_step2": ".zshrc に keychain:// 参照を設定",
        "completion_secretref_step3": "akc run -- <command> で実行",
        "completion_proxy_step1": "AI KeyChain を常時起動（メニューバーに常駐）",
        "completion_proxy_step2": "ターミナルで claude などをそのまま使う",
        "completion_proxy_step3": "プロキシが自動で認証 — キーは env に出ない",
        "completion_mode_change_hint": "メニューバーからいつでもモードを変更できます",
        "completion_secretref_warning": "akc run なしで直接実行すると keychain:// がそのまま送信されます",
        "completion_proxy_hint": "接続不能時はメニューバー → Recovery Guide で復旧できます",

        // Onboarding Steps
        "step_language": "言語",
        "step_welcome": "ようこそ",
        "step_mode": "モード選択",
        "step_keys": "キー登録",
        "step_shell": "シェル設定",
        "step_complete": "完了",

        // MenuBar
        "menubar_mode": "モード: %@",
        "menubar_proxy_running": "Proxy: 稼働中",
        "menubar_proxy_stopped": "Proxy: 停止中",
        "menubar_port": "Port: %@",
        "menubar_requests": "リクエスト: %@",
        "menubar_change_mode": "モード変更...",
        "menubar_stop_proxy": "Proxy 停止",
        "menubar_start_proxy": "Proxy 起動",
        "menubar_change_port": "ポート変更...",
        "menubar_recovery": "Recovery Guide...",
        "menubar_open_keychain": "KeyChain を開く...",
        "menubar_open_keychain_access": "Keychain Access を開く",
        "menubar_launch_at_login": "ログイン時に起動",
        "menubar_shell_cleanup": "シェルクリーンアップ...",
        "menubar_show_tutorial": "チュートリアル表示",
        "menubar_language": "言語 / Language",
        "menubar_quit": "終了",

        // MainView
        "main_search": "キーを検索...",
        "main_mode_hint": "モード — クリックで変更",
        "main_transfer": "転送",
        "main_user_manual": "ユーザーマニュアル",
        "main_change_mode": "モード変更...",
        "main_recovery": "Recovery Guide...",
        "main_shell_cleanup": "シェルクリーンアップ...",
        "main_show_tutorial": "チュートリアル表示",
        "main_help": "ヘルプ",

        // Sidebar
        "sidebar_all_keys": "すべてのキー",
        "sidebar_categories": "カテゴリ",
        "sidebar_custom": "カスタム",
        "sidebar_manage_categories": "カテゴリ管理",
        "sidebar_configured": "設定済み",
        "sidebar_pending": "未設定",

        // KeyList
        "keylist_keys": "件",
        "keylist_import": "インポート",
        "keylist_add_key": "キー追加",
        "keylist_no_keys": "キーが見つかりません",
        "keylist_no_keys_desc": "キーを追加またはインポートして始めましょう。",
        "keylist_edit": "編集",
        "keylist_copy_env": "Env 名をコピー",
        "keylist_copy_value": "値をコピー",
        "keylist_open_setup": "セットアップページを開く",

        // HelpView
        "help_title": "ユーザーマニュアル",
        "help_overview": "概要",
        "help_overview_desc": "AI KeyChain は AI API キーを macOS Keychain に安全に保管し、プロキシ経由で環境変数に露出させずに利用できるアプリです。",
        "help_mechanism": "仕組み",
        "help_export": "エクスポート",
        "help_shortcuts": "キーボードショートカット",
        "help_show_tutorial": "チュートリアルを再表示",

        // RecoveryView
        "recovery_title": "Recovery Guide",
        "recovery_subtitle": "プロキシモード復旧ガイド",
        "recovery_running": "Proxy: 稼働中 (Port %@)",
        "recovery_stopped": "Proxy: 停止中",
        "recovery_mode": "モード: %@",
        "recovery_restart_title": "AI KeyChain を再起動",
        "recovery_restart_desc": "最も簡単な方法です。アプリを再起動すればプロキシが自動復旧します。",
        "recovery_switch_title": "Standard モードに切り替え",
        "recovery_switch_desc": "プロキシを使わず、従来の Keychain 直接参照に戻します。",
        "recovery_manual_title": "設定ファイルを手動削除（即時復旧）",
        "recovery_manual_desc": "ターミナルで以下を実行すると、プロキシ設定が即座に解除されます。",
        "recovery_zshrc_title": ".zshrc のフックを削除（完全除去）",
        "recovery_faq": "FAQ",

        // ModeSelectView (standalone)
        "modeselect_title": "Key Management Mode",
        "modeselect_subtitle": "API キーの管理方式を選択",
        "modeselect_standard_subtitle": "通常 Keychain 参照",
        "modeselect_secretref_subtitle": "keychain:// 参照（1Password 方式）",
        "modeselect_proxy_subtitle": "プロキシ経由（上級者向け）",
        "modeselect_hint": "適用ボタンでモードを切り替えます",
        "modeselect_comparison": "モード比較の詳細",

        // ExportView
        "export_title": "キーをエクスポート",
        "export_format": "フォーマット",
        "export_count": "%d 件の設定済みキーをエクスポート",
        "export_copy": "クリップボードにコピー",
        "export_copied": "コピー済み！",
        "export_save": "ファイルに保存...",

        // ProxyConsent
        "consent_title": "Proxy Mode — 利用上の注意",
        "consent_agree": "上記の注意事項を理解し、自己責任で利用します",
        "consent_enable": "同意して有効化",
    ]

    private static let en: [String: String] = [
        // Navigation
        "back": "Back",
        "next": "Next",
        "skip": "Skip",
        "cancel": "Cancel",
        "done": "Done",
        "apply": "Apply",
        "save": "Save",
        "delete": "Delete",
        "copy": "Copy",

        // Onboarding - Language
        "language_title": "Select Language",
        "language_subtitle": "Choose the display language for the app.\nYou can change this anytime later.",

        // Onboarding - Welcome
        "welcome_title": "AI KeyChain",
        "welcome_subtitle": "Securely manage AI API keys on macOS",
        "welcome_feature1_title": "Secure Keychain Storage",
        "welcome_feature1_desc": "API keys are encrypted in macOS Keychain",
        "welcome_feature2_title": "Hidden from Environment",
        "welcome_feature2_desc": "Keys are invisible even when AI reads env variables",
        "welcome_feature3_title": "Auto-inject via Local Proxy",
        "welcome_feature3_desc": "Auth headers are securely added in the background",

        // Onboarding - Mode Select
        "mode_select_title": "Choose Your Mode",
        "mode_select_subtitle": "Select how you want to manage API keys.\nYou can change this anytime later.",
        "mode_standard_subtitle": "Simple & Stable",
        "mode_standard_pro": "Easy to set up",
        "mode_standard_con": "Keys visible in env",
        "mode_secretref_subtitle": "1Password-style",
        "mode_secretref_pro": "No key values in env",
        "mode_secretref_con": "Requires akc run",
        "mode_proxy_subtitle": "Most Secure",
        "mode_proxy_pro": "Keys fully hidden",
        "mode_proxy_con": "App must stay running",
        "mode_proxy_warning": "Proxy mode requires the app to be always running. Recovery methods are available in the app.",
        "mode_secretref_info": "Wrap your command with akc run -- <command> to auto-resolve keychain:// references.",

        // Onboarding - Flow Diagram
        "flow_terminal": "Terminal / AI Tool",
        "flow_api_server": "API Server",
        "flow_standard_detail": "export API_KEY=$(security ...)",
        "flow_standard_arrow": "Send API key directly",
        "flow_secretref_detail": "env: keychain://API_KEY",
        "flow_secretref_arrow1": "akc run resolves from Keychain",
        "flow_secretref_child": "Child Process",
        "flow_secretref_child_detail": "Injects actual key values to env",
        "flow_secretref_arrow2": "Send API key",
        "flow_proxy_detail": "No keys in env",
        "flow_proxy_arrow1": "Unauthenticated request",
        "flow_proxy_box": "AI KeyChain Proxy",
        "flow_proxy_box_detail": "Keychain → Header injection",
        "flow_proxy_arrow2": "Authenticated request",

        // Onboarding - Register Keys
        "register_title": "Register Your Keys",
        "register_subtitle": "Register the API keys you want to manage.\nYou can add or edit them later from the main screen.",
        "register_tip": "Tip: Double-click or right-click a key → Edit on the main screen",

        // Onboarding - Shell Setup
        "shell_title": "Connect Your Shell",
        "shell_subtitle": "Just one line in .zshrc — BASE_URL is auto-set\nonly while the proxy is running.",
        "shell_port": "Port:",
        "shell_default_port": "(default: %@)",
        "shell_zshrc_label": "Added to ~/.zshrc:",
        "shell_note1": "~/.aikeychain_proxy exists only while the proxy is running",
        "shell_note2": "The file is auto-deleted when the proxy stops",
        "shell_note3": "No stale BASE_URL issues",
        "shell_configured": "Configured",
        "shell_enable_proxy": "Enable Secure Proxy",
        "shell_key_safe": "API key values are never written. It's safe.",
        "shell_port_error": "Port must be between 1024 and 65535",

        // Onboarding - Completion
        "completion_title": "Setup Complete!",
        "get_started": "Get Started",
        "completion_standard": "Standard mode setup complete",
        "completion_secretref": "Secret Reference mode setup complete",
        "completion_proxy": "Proxy mode setup complete",
        "completion_standard_step1": "Register API keys in Keychain",
        "completion_standard_step2": "Set environment variables via .zshrc export",
        "completion_standard_step3": "Use AI tools directly in terminal",
        "completion_secretref_step1": "Register API keys in Keychain",
        "completion_secretref_step2": "Set keychain:// references in .zshrc",
        "completion_secretref_step3": "Run with akc run -- <command>",
        "completion_proxy_step1": "Keep AI KeyChain running (menu bar resident)",
        "completion_proxy_step2": "Use claude etc. directly in terminal",
        "completion_proxy_step3": "Proxy auto-authenticates — keys never in env",
        "completion_mode_change_hint": "You can change the mode anytime from the menu bar",
        "completion_secretref_warning": "Running without akc run will send keychain:// as-is",
        "completion_proxy_hint": "If connection fails, use menu bar → Recovery Guide",

        // Onboarding Steps
        "step_language": "Language",
        "step_welcome": "Welcome",
        "step_mode": "Choose Mode",
        "step_keys": "Register Keys",
        "step_shell": "Shell Setup",
        "step_complete": "Complete!",

        // MenuBar
        "menubar_mode": "Mode: %@",
        "menubar_proxy_running": "Proxy: Running",
        "menubar_proxy_stopped": "Proxy: Stopped",
        "menubar_port": "Port: %@",
        "menubar_requests": "Requests: %@",
        "menubar_change_mode": "Change Mode...",
        "menubar_stop_proxy": "Stop Proxy",
        "menubar_start_proxy": "Start Proxy",
        "menubar_change_port": "Change Port...",
        "menubar_recovery": "Recovery Guide...",
        "menubar_open_keychain": "Open KeyChain...",
        "menubar_open_keychain_access": "Open Keychain Access",
        "menubar_launch_at_login": "Launch at Login",
        "menubar_shell_cleanup": "Shell Cleanup...",
        "menubar_show_tutorial": "Show Tutorial",
        "menubar_language": "言語 / Language",
        "menubar_quit": "Quit",

        // MainView
        "main_search": "Search keys...",
        "main_mode_hint": "Mode — Click to change",
        "main_transfer": "Transfer",
        "main_user_manual": "User Manual",
        "main_change_mode": "Change Mode...",
        "main_recovery": "Recovery Guide...",
        "main_shell_cleanup": "Shell Cleanup...",
        "main_show_tutorial": "Show Tutorial",
        "main_help": "Help",

        // Sidebar
        "sidebar_all_keys": "All Keys",
        "sidebar_categories": "Categories",
        "sidebar_custom": "Custom",
        "sidebar_manage_categories": "Manage Categories",
        "sidebar_configured": "configured",
        "sidebar_pending": "pending",

        // KeyList
        "keylist_keys": "keys",
        "keylist_import": "Import",
        "keylist_add_key": "Add Key",
        "keylist_no_keys": "No Keys Found",
        "keylist_no_keys_desc": "Add Key or Import to get started.",
        "keylist_edit": "Edit",
        "keylist_copy_env": "Copy Env Name",
        "keylist_copy_value": "Copy Value",
        "keylist_open_setup": "Open Setup Page",

        // HelpView
        "help_title": "User Manual",
        "help_overview": "Overview",
        "help_overview_desc": "AI KeyChain securely stores AI API keys in macOS Keychain and lets you use them via proxy without exposing them in environment variables.",
        "help_mechanism": "How It Works",
        "help_export": "Export",
        "help_shortcuts": "Keyboard Shortcuts",
        "help_show_tutorial": "Show Tutorial Again",

        // RecoveryView
        "recovery_title": "Recovery Guide",
        "recovery_subtitle": "Proxy Mode Recovery Guide",
        "recovery_running": "Proxy: Running (Port %@)",
        "recovery_stopped": "Proxy: Stopped",
        "recovery_mode": "Mode: %@",
        "recovery_restart_title": "Restart AI KeyChain",
        "recovery_restart_desc": "The simplest method. Restarting the app will auto-recover the proxy.",
        "recovery_switch_title": "Switch to Standard Mode",
        "recovery_switch_desc": "Stop using proxy and revert to direct Keychain reference.",
        "recovery_manual_title": "Manually Delete Config File (Instant Recovery)",
        "recovery_manual_desc": "Run the following in Terminal to immediately remove proxy settings.",
        "recovery_zshrc_title": "Remove .zshrc Hook (Complete Removal)",
        "recovery_faq": "FAQ",

        // ModeSelectView (standalone)
        "modeselect_title": "Key Management Mode",
        "modeselect_subtitle": "Select API key management mode",
        "modeselect_standard_subtitle": "Standard Keychain reference",
        "modeselect_secretref_subtitle": "keychain:// reference (1Password-style)",
        "modeselect_proxy_subtitle": "Via proxy (advanced)",
        "modeselect_hint": "Click Apply to switch mode",
        "modeselect_comparison": "Mode Comparison Details",

        // ExportView
        "export_title": "Export Keys",
        "export_format": "Format",
        "export_count": "%d configured keys will be exported",
        "export_copy": "Copy to Clipboard",
        "export_copied": "Copied!",
        "export_save": "Save to File...",

        // ProxyConsent
        "consent_title": "Proxy Mode — Important Notice",
        "consent_agree": "I understand the above and accept responsibility",
        "consent_enable": "Agree & Enable",
    ]
}
