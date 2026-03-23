import Foundation
import Observation
import ServiceManagement

/// アプリ全体の共有状態
/// プロキシサーバーとメニューバーの状態を一元管理する
@Observable
final class AppState {
    static let shared = AppState()

    let proxyServer = ProxyServer()

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

    private init() {}

    /// アプリ起動時にプロキシを自動起動
    func startProxyIfNeeded() {
        guard !proxyServer.isRunning else { return }
        do {
            try proxyServer.start()
        } catch {
            proxyServer.lastError = error.localizedDescription
        }
    }
}
