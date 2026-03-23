import SwiftUI

@main
struct AIkeychainApp: App {
    @State private var appState = AppState.shared

    var body: some Scene {
        // メインウィンドウ（キー管理UI）
        Window("AI KeyChain", id: "main") {
            MainView()
                .onAppear {
                    appState.startProxyIfNeeded()
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 800, height: 550)

        // メニューバー常駐
        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            Image(systemName: appState.proxyServer.isRunning ? "key.fill" : "key")
        }
    }
}
