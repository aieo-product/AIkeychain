import SwiftUI

/// アップグレードツアーの提示 payload (#194)。`.sheet(item:)` で使うため Identifiable。
/// 1 起動につき高々 1 回の提示なので id は固定でよい。
private struct UpgradeTourPayload: Identifiable {
    var id: Int { 0 }
    let keyNames: [String]
}

struct MainView: View {
    @State private var viewModel = KeyListViewModel()
    @State private var showingShare = false
    @State private var showingHelp = false
    // v2.0 (#188): アップグレードで取り残された v1 キーがあれば、通常の onboarding より
    // 先に再登録ツアーを出す。新規インストール（旧キー無し）は従来どおり onboarding。
    // スキャンは onAppear で 1 回だけ（@State のデフォルト式は struct 再構築のたびに
    // 評価され、全 keychain 列挙をメインスレッドで反復してしまうため空で初期化する）。
    // 提示は `.sheet(item:)` を使う: `.sheet(isPresented:)` + 別 @State だと、提示時に
    // コンテンツクロージャが更新前の値（空配列）で評価され「再登録が必要なキー（0 件）」
    // になる stale-sheet 挙動を実機で確認した (#194)。payload に検出結果を持たせる。
    @State private var upgradeTour: UpgradeTourPayload?
    @State private var didScanLegacy = false
    @State private var showingOnboarding = false
    @State private var showingCleanup = false
    @State private var showingModeSelect = false
    @State private var showingRecovery = false

    private var appState: AppState { .shared }

    @ViewBuilder
    private var modeStatusLabel: some View {
        let mode = appState.keyManagementMode
        let isRunning = appState.proxyServer.isRunning

        let bgColor: Color = switch mode {
        case .proxy: isRunning ? Color.green.opacity(0.12) : Color.red.opacity(0.12)
        case .secretReference: AppColors.cloudBlue.opacity(0.1)
        case .standard: Color.gray.opacity(0.1)
        }
        let borderColor: Color = switch mode {
        case .proxy: isRunning ? Color.green.opacity(0.3) : Color.red.opacity(0.3)
        case .secretReference: AppColors.cloudBlue.opacity(0.25)
        case .standard: Color.gray.opacity(0.2)
        }

        HStack(spacing: 5) {
            switch mode {
            case .proxy:
                Circle()
                    .fill(isRunning ? Color.green : Color.red)
                    .frame(width: 7, height: 7)
                Text("Proxy")
                    .font(.system(size: 11, weight: .medium))
            case .secretReference:
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 11))
                Text("Secret Ref")
                    .font(.system(size: 11, weight: .medium))
            case .standard:
                Image(systemName: "key.fill")
                    .font(.system(size: 11))
                Text("Standard")
                    .font(.system(size: 11, weight: .medium))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(bgColor, in: Capsule())
        .overlay(Capsule().stroke(borderColor, lineWidth: 1))
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel)
                .id(appState.appLanguage)
        } detail: {
            if viewModel.selectedCategory == .activity {
                ActivityView()
            } else {
                KeyListView(viewModel: viewModel)
            }
        }
        .searchable(text: $viewModel.searchText, prompt: L10n.t("main_search"))
        .toolbar {
            // Proxy status button (prominent)
            ToolbarItem(placement: .navigation) {
                Button {
                    showingModeSelect = true
                } label: {
                    modeStatusLabel
                }
                .help(L10n.t("main_mode_hint"))
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingShare = true
                } label: {
                    Label(L10n.t("main_transfer"), systemImage: "lock.shield")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(L10n.t("main_user_manual")) {
                        showingHelp = true
                    }
                    Button(L10n.t("main_change_mode")) {
                        showingModeSelect = true
                    }
                    if appState.isProxyMode {
                        Button(L10n.t("main_recovery")) {
                            showingRecovery = true
                        }
                        Button(L10n.t("main_shell_cleanup")) {
                            showingCleanup = true
                        }
                    }
                    Divider()

                    // Language switcher
                    Menu {
                        ForEach(AppLanguage.allCases) { lang in
                            Button {
                                appState.appLanguage = lang
                            } label: {
                                HStack {
                                    Text("\(lang.flag) \(lang.displayName)")
                                    if appState.appLanguage == lang {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Label(L10n.t("menubar_language"), systemImage: "globe")
                    }

                    Button(L10n.t("main_show_tutorial")) {
                        showingOnboarding = true
                    }
                } label: {
                    Label(L10n.t("main_help"), systemImage: "questionmark.circle")
                }
            }
        }
        .sheet(isPresented: $viewModel.showingEditor) {
            viewModel.loadKeys()
        } content: {
            KeyEditorView(
                editingKey: viewModel.editingKey,
                onSave: { viewModel.loadKeys() }
            )
        }
        .sheet(isPresented: $showingShare) {
            ShareKeysView(keys: viewModel.keys) {
                viewModel.loadKeys()
            }
        }
        .sheet(isPresented: $showingHelp) {
            HelpView()
        }
        .sheet(isPresented: $showingOnboarding) {
            OnboardingView()
        }
        .sheet(item: $upgradeTour) { payload in
            UpgradeTourView(legacyKeyNames: payload.keyNames)
        }
        .sheet(isPresented: $showingCleanup) {
            CleanupView()
        }
        .sheet(isPresented: $showingModeSelect) {
            ModeSelectView()
        }
        .sheet(isPresented: $showingRecovery) {
            RecoveryView()
        }
        .frame(minWidth: 750, minHeight: 500)
        .onAppear {
            // 起動時に 1 回だけ: 取り残された v1 キーをバックグラウンドで無音スキャンし、
            // あればツアーを最優先。無ければ（新規インストール等）通常の onboarding。
            guard !didScanLegacy else { return }
            didScanLegacy = true
            Task.detached(priority: .utility) {
                let found = LegacyKeyScanner.unmigratedKeyNames()
                await MainActor.run {
                    if UpgradeTourView.shouldShow(legacyKeyNames: found) {
                        upgradeTour = UpgradeTourPayload(keyNames: found)
                    } else if !OnboardingViewModel.hasCompleted {
                        showingOnboarding = true
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showOnboarding)) { _ in
            showingOnboarding = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showCleanup)) { _ in
            showingCleanup = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showModeSelect)) { _ in
            showingModeSelect = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showRecovery)) { _ in
            showingRecovery = true
        }
    }
}
