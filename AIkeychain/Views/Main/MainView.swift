import SwiftUI

struct MainView: View {
    @State private var viewModel = KeyListViewModel()
    @State private var showingShare = false
    @State private var showingHelp = false
    @State private var showingOnboarding = !OnboardingViewModel.hasCompleted
    @State private var showingCleanup = false
    @State private var showingModeSelect = false
    @State private var showingRecovery = false

    private var appState: AppState { .shared }

    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel)
        } detail: {
            KeyListView(viewModel: viewModel)
        }
        .searchable(text: $viewModel.searchText, prompt: "Search keys...")
        .toolbar {
            // Proxy status button (prominent)
            ToolbarItem(placement: .navigation) {
                Button {
                    showingModeSelect = true
                } label: {
                    HStack(spacing: 5) {
                        if appState.isProxyMode {
                            Circle()
                                .fill(appState.proxyServer.isRunning ? .green : .red)
                                .frame(width: 7, height: 7)
                            Text("Proxy")
                                .font(.system(size: 11, weight: .medium))
                        } else {
                            Image(systemName: "shield.slash")
                                .font(.system(size: 11))
                            Text("Standard")
                                .font(.system(size: 11, weight: .medium))
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        appState.isProxyMode
                            ? (appState.proxyServer.isRunning ? Color.green.opacity(0.12) : Color.red.opacity(0.12))
                            : Color.gray.opacity(0.1),
                        in: Capsule()
                    )
                    .overlay(
                        Capsule()
                            .stroke(
                                appState.isProxyMode
                                    ? (appState.proxyServer.isRunning ? Color.green.opacity(0.3) : Color.red.opacity(0.3))
                                    : Color.gray.opacity(0.2),
                                lineWidth: 1
                            )
                    )
                }
                .help(appState.isProxyMode ? "Proxy Mode — Click to change" : "Standard Mode — Click to enable Proxy")
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingShare = true
                } label: {
                    Label("Transfer", systemImage: "lock.shield")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("User Manual") {
                        showingHelp = true
                    }
                    Button("Change Mode...") {
                        showingModeSelect = true
                    }
                    if appState.isProxyMode {
                        Button("Recovery Guide...") {
                            showingRecovery = true
                        }
                        Button("Shell Cleanup...") {
                            showingCleanup = true
                        }
                    }
                    Divider()
                    Button("Show Tutorial") {
                        showingOnboarding = true
                    }
                } label: {
                    Label("Help", systemImage: "questionmark.circle")
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
