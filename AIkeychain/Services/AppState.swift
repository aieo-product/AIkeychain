import Foundation
import Observation
import ServiceManagement

/// キー管理モード
enum KeyManagementMode: String {
    /// 通常モード: .zshrc に security find-generic-password で直接参照
    case standard
    /// プロキシモード: ローカルプロキシ経由で認証ヘッダを注入
    case proxy
}

/// アプリ全体の共有状態
/// プロキシサーバーとメニューバーの状態を一元管理する
@Observable
final class AppState {
    static let shared = AppState()

    static let defaultPort: UInt16 = 18121
    private static let portKey = "proxy_port"
    private static let modeKey = "key_management_mode"
    private static let proxyConsentKey = "proxy_mode_consent"

    let proxyServer = ProxyServer()
    let proxyLogStore = ProxyLogStore()

    /// ユーザーが選択したキー管理モード（UserDefaults で永続化）
    var keyManagementMode: KeyManagementMode {
        get {
            let raw = UserDefaults.standard.string(forKey: Self.modeKey) ?? ""
            return KeyManagementMode(rawValue: raw) ?? .standard
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.modeKey)
        }
    }

    /// プロキシモードの同意済みフラグ
    var hasProxyConsent: Bool {
        get { UserDefaults.standard.bool(forKey: Self.proxyConsentKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.proxyConsentKey) }
    }

    /// プロキシモードが有効か
    var isProxyMode: Bool {
        keyManagementMode == .proxy
    }

    /// ユーザーが選択したポート番号（UserDefaults で永続化）
    var proxyPort: UInt16 {
        get {
            let stored = UserDefaults.standard.integer(forKey: Self.portKey)
            return stored > 0 ? UInt16(clamping: stored) : Self.defaultPort
        }
        set {
            UserDefaults.standard.set(Int(newValue), forKey: Self.portKey)
            proxyServer.port = newValue
        }
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Silently handle - UI will reflect actual state
            }
        }
    }

    private init() {
        // 保存済みポート番号を復元
        proxyServer.port = proxyPort
    }

    /// アプリ起動時にプロキシを自動起動（プロキシモード時のみ）
    func startProxyIfNeeded() {
        // Standard モードではプロキシを起動しない
        guard isProxyMode else {
            SetupManager.deactivateProxy()
            return
        }
        guard !proxyServer.isRunning else { return }
        // 前回の強制終了で残った設定ファイルをクリーンアップしてから起動
        SetupManager.deactivateProxy()
        do {
            try proxyServer.start()
            try? SetupManager.activateProxy(port: proxyPort)
        } catch {
            proxyServer.lastError = error.localizedDescription
        }
    }

    /// プロキシを停止
    func stopProxy() {
        proxyServer.stop()
        SetupManager.deactivateProxy()
    }

    /// ポート変更（プロキシ再起動が必要）
    func changePort(to newPort: UInt16) {
        let wasRunning = proxyServer.isRunning
        if wasRunning {
            stopProxy()
        }
        proxyPort = newPort
        if wasRunning {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.startProxyIfNeeded()
            }
        }
    }

    /// モード切替
    func switchMode(to mode: KeyManagementMode) {
        if mode == .standard {
            // プロキシ停止 & 設定ファイル削除
            stopProxy()
        }
        keyManagementMode = mode
        if mode == .proxy {
            startProxyIfNeeded()
        }
    }
}
