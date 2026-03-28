import SwiftUI

struct OnboardingView: View {
    @State private var viewModel = OnboardingViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Step indicator header
            HStack(spacing: 0) {
                ForEach(OnboardingStep.allCases) { step in
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(step.rawValue <= viewModel.currentStep.rawValue
                                      ? AppColors.aiPurple : Color.gray.opacity(0.2))
                                .frame(width: 32, height: 32)
                            Image(systemName: step.systemImage)
                                .font(.system(size: 14))
                                .foregroundStyle(step.rawValue <= viewModel.currentStep.rawValue
                                                 ? .white : .secondary)
                        }
                        Text(step.title)
                            .font(.system(size: 9, weight: step == viewModel.currentStep ? .semibold : .regular))
                            .foregroundStyle(step == viewModel.currentStep ? .primary : .secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)

                    if step.rawValue < OnboardingStep.allCases.count - 1 {
                        Rectangle()
                            .fill(step.rawValue < viewModel.currentStep.rawValue
                                  ? AppColors.aiPurple : Color.gray.opacity(0.2))
                            .frame(height: 2)
                            .frame(maxWidth: 40)
                            .padding(.bottom, 18)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 8)

            Divider()

            // Content area with transition
            Group {
                switch viewModel.currentStep {
                case .welcome:
                    WelcomeStepView()
                case .modeSelect:
                    ModeSelectStepView()
                case .registerKeys:
                    RegisterKeysStepView()
                case .setupShell:
                    SetupShellStepView()
                case .completion:
                    CompletionStepView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
            .id(viewModel.currentStep) // force re-render for transition

            Divider()

            // Navigation buttons
            HStack {
                if viewModel.canGoBack {
                    Button {
                        withAnimation(AppAnimations.transition) {
                            viewModel.back()
                        }
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                }

                Spacer()

                if viewModel.currentStep.canSkip {
                    Button("Skip") {
                        withAnimation(AppAnimations.transition) {
                            viewModel.next()
                        }
                    }
                    .foregroundStyle(.secondary)
                }

                if viewModel.isLastStep {
                    Button {
                        viewModel.complete()
                        dismiss()
                    } label: {
                        Label("Get Started", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button {
                        withAnimation(AppAnimations.transition) {
                            viewModel.next()
                        }
                    } label: {
                        Label("Next", systemImage: "chevron.right")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 660, height: 600)
    }
}

// MARK: - Step Views

struct WelcomeStepView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 20)

                Image(systemName: "key.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(AppColors.accentGradient)

                Text("AI KeyChain")
                    .font(AppFonts.pageTitle)

                Text("AI API キーをセキュアに管理する macOS アプリ")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 14) {
                    FeatureRow(icon: "lock.shield", color: AppColors.aiPurple,
                               title: "Keychain で安全に保管",
                               desc: "API キーは macOS Keychain に暗号化保存")
                    FeatureRow(icon: "eye.slash", color: AppColors.cloudBlue,
                               title: "環境変数に露出しない",
                               desc: "AI が env コマンドで見てもキーは表示されない")
                    FeatureRow(icon: "arrow.triangle.2.circlepath", color: AppColors.commGreen,
                               title: "ローカルプロキシで自動注入",
                               desc: "認証ヘッダをバックグラウンドで安全に追加")
                }
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 40)

                Spacer(minLength: 20)
            }
            .padding(.horizontal)
        }
    }
}

struct ModeSelectStepView: View {
    @State private var selectedMode: KeyManagementMode = AppState.shared.keyManagementMode
    @State private var showConsent = false
    @State private var animateStandard = false
    @State private var animateProxy = false
    @State private var showDiagram = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Spacer(minLength: 12)

                Text("Choose Your Mode")
                    .font(AppFonts.sectionTitle)

                Text("API キーの管理方式を選んでください。\nあとからいつでも変更できます。")
                    .font(AppFonts.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                // Mode comparison cards
                HStack(spacing: 14) {
                    // Standard card
                    OnboardingModeCard(
                        isSelected: selectedMode == .standard,
                        icon: "key.fill",
                        color: AppColors.commGreen,
                        title: "Standard",
                        subtitle: "安定・シンプル",
                        items: [
                            ("checkmark.circle", "プロキシ不要", AppColors.commGreen),
                            ("checkmark.circle", "設定がシンプル", AppColors.commGreen),
                            ("exclamationmark.triangle", "env にキーが見える", .orange),
                            ("exclamationmark.triangle", "SSH で承認が必要な場合あり", .orange),
                        ]
                    ) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            selectedMode = .standard
                            AppState.shared.switchMode(to: .standard)
                        }
                    }
                    .scaleEffect(animateStandard ? 1.0 : 0.9)
                    .opacity(animateStandard ? 1.0 : 0)

                    // Proxy card
                    OnboardingModeCard(
                        isSelected: selectedMode == .proxy,
                        icon: "shield.checkered",
                        color: AppColors.aiPurple,
                        title: "Proxy",
                        subtitle: "高セキュリティ",
                        items: [
                            ("checkmark.circle", "env にキーが露出しない", AppColors.aiPurple),
                            ("checkmark.circle", "SSH / Tailscale 対応", AppColors.aiPurple),
                            ("exclamationmark.triangle", "アプリ常時起動が必要", .orange),
                            ("exclamationmark.triangle", "停止時に接続不可", .orange),
                        ]
                    ) {
                        if AppState.shared.hasProxyConsent {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                selectedMode = .proxy
                                AppState.shared.switchMode(to: .proxy)
                            }
                        } else {
                            showConsent = true
                        }
                    }
                    .scaleEffect(animateProxy ? 1.0 : 0.9)
                    .opacity(animateProxy ? 1.0 : 0)
                }
                .padding(.horizontal, 20)

                // Animated flow diagram
                if showDiagram {
                    VStack(spacing: 0) {
                        if selectedMode == .standard {
                            FlowBox(label: "Terminal / AI ツール", detail: "export API_KEY=$(security ...)", color: AppColors.commGreen, icon: "terminal")
                            FlowArrow(label: "API キーを直接送信")
                            FlowBox(label: "API Server", detail: "api.anthropic.com", color: AppColors.cloudBlue, icon: "cloud.fill")
                        } else {
                            FlowBox(label: "Terminal / AI ツール", detail: "env にキーなし", color: AppColors.aiPurple, icon: "terminal")
                            FlowArrow(label: "認証なしリクエスト")
                            FlowBox(label: "AI KeyChain Proxy", detail: "Keychain → ヘッダ注入", color: AppColors.cloudBlue, icon: "key.fill")
                            FlowArrow(label: "認証済みリクエスト")
                            FlowBox(label: "API Server", detail: "api.anthropic.com", color: AppColors.commGreen, icon: "cloud.fill")
                        }
                    }
                    .padding(.horizontal, 60)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.95).combined(with: .opacity),
                        removal: .scale(scale: 0.95).combined(with: .opacity)
                    ))
                    .id(selectedMode) // re-animate on mode change
                }

                if selectedMode == .proxy {
                    Label("Proxy モードはアプリ常時起動が前提です。停止時の復旧方法はアプリ内で確認できます。",
                          systemImage: "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 30)
                        .transition(.opacity)
                }

                Spacer(minLength: 12)
            }
            .padding(.horizontal)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1)) {
                animateStandard = true
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.25)) {
                animateProxy = true
            }
            withAnimation(.easeOut(duration: 0.4).delay(0.5)) {
                showDiagram = true
            }
        }
        .sheet(isPresented: $showConsent) {
            ProxyConsentView {
                AppState.shared.hasProxyConsent = true
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    selectedMode = .proxy
                    AppState.shared.switchMode(to: .proxy)
                }
            }
        }
    }
}

private struct OnboardingModeCard: View {
    let isSelected: Bool
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    let items: [(String, String, Color)]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(isSelected ? color : Color.gray.opacity(0.1))
                        .frame(width: 50, height: 50)
                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundStyle(isSelected ? .white : .secondary)
                }

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Divider()
                    .padding(.horizontal, 8)

                VStack(alignment: .leading, spacing: 5) {
                    ForEach(items, id: \.1) { img, text, itemColor in
                        HStack(spacing: 5) {
                            Image(systemName: img)
                                .font(.system(size: 9))
                                .foregroundStyle(itemColor)
                                .frame(width: 14)
                            Text(text)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .background(
                isSelected ? color.opacity(0.06) : Color.clear,
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? color : Color.gray.opacity(0.15), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct RegisterKeysStepView: View {
    @State private var keyListVM = KeyListViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Spacer(minLength: 20)

                Image(systemName: "plus.circle")
                    .font(.system(size: 48))
                    .foregroundStyle(AppColors.commGreen)

                Text("Register Your Keys")
                    .font(AppFonts.sectionTitle)

                Text("管理したい API キーを登録しましょう。\nあとからメイン画面でいつでも追加・編集できます。")
                    .font(AppFonts.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                // Quick status
                VStack(spacing: 10) {
                    ForEach(KeyCategory.allCases) { category in
                        HStack(spacing: 10) {
                            CategoryIcon(category: category, size: 26)
                            Text(category.rawValue)
                                .font(.system(size: 13))
                            Spacer()
                            let total = keyListVM.builtinCategoryCount(for: category)
                            let configured = keyListVM.builtinCategoryConfiguredCount(for: category)
                            HStack(spacing: 4) {
                                Text("\(configured)")
                                    .foregroundStyle(configured > 0 ? AppColors.configured : .secondary)
                                Text("/")
                                    .foregroundStyle(.quaternary)
                                Text("\(total)")
                                    .foregroundStyle(.secondary)
                            }
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                        }
                    }
                }
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 50)

                Label("Tip: メイン画面でキーをダブルクリック or 右クリック → Edit",
                      systemImage: "lightbulb")
                    .font(AppFonts.caption)
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 20)
            }
            .padding(.horizontal)
        }
    }
}

struct SetupShellStepView: View {
    @State private var isConfigured = SetupManager.isConfigured()
    @State private var errorMessage: String?
    @State private var portText = "\(AppState.shared.proxyPort)"

    private var currentPort: UInt16 {
        AppState.shared.proxyPort
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 20)

                Image(systemName: "terminal")
                    .font(.system(size: 48))
                    .foregroundStyle(AppColors.gitOrange)

                Text("Connect Your Shell")
                    .font(AppFonts.sectionTitle)

                Text(".zshrc に1行追加するだけで、プロキシ起動中のみ\nBASE_URL が自動設定されます。")
                    .font(AppFonts.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                // Port selector
                HStack(spacing: 8) {
                    Text("Port:")
                        .font(.system(size: 13, weight: .medium))
                    TextField("Port", text: $portText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .onSubmit { applyPort() }
                    Button("Apply") { applyPort() }
                        .controlSize(.small)
                    Text("(default: \(AppState.defaultPort))")
                        .font(AppFonts.caption)
                        .foregroundStyle(.tertiary)
                }

                // Preview
                VStack(alignment: .leading, spacing: 6) {
                    Text("~/.zshrc に追記される内容:")
                        .font(AppFonts.badge)
                        .foregroundStyle(.secondary)

                    Text("[ -f ~/.aikeychain_proxy ] && source ~/.aikeychain_proxy")
                        .font(AppFonts.code)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 40)

                VStack(alignment: .leading, spacing: 4) {
                    Label("プロキシ起動中のみ ~/.aikeychain_proxy が存在します", systemImage: "checkmark.shield")
                    Label("プロキシ停止時はファイルが自動削除されます", systemImage: "xmark.shield")
                    Label("BASE_URL が残り続ける問題は発生しません", systemImage: "shield.checkered")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

                if isConfigured {
                    Label("設定済み", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(AppColors.configured)
                        .font(.system(size: 14, weight: .medium))
                } else {
                    Button("Enable Secure Proxy") {
                        do {
                            try SetupManager.configure()
                            withAnimation { isConfigured = true }
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                if let error = errorMessage {
                    Text(error)
                        .font(AppFonts.caption)
                        .foregroundStyle(.red)
                }

                Label("API キーの値は書き込まれません。安全です。",
                      systemImage: "lock.shield")
                    .font(AppFonts.caption)
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 20)
            }
            .padding(.horizontal)
        }
    }

    private func applyPort() {
        guard let value = UInt16(portText), value >= 1024 else {
            errorMessage = "ポート番号は 1024〜65535 の範囲で指定してください"
            return
        }
        errorMessage = nil
        AppState.shared.changePort(to: value)
    }
}

struct CompletionStepView: View {
    private var isProxy: Bool { AppState.shared.isProxyMode }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 30)

                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(AppColors.configured)

                Text("Setup Complete!")
                    .font(AppFonts.pageTitle)

                Text(isProxy
                     ? "Proxy モードでセットアップ完了"
                     : "Standard モードでセットアップ完了")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)

                if isProxy {
                    VStack(alignment: .leading, spacing: 14) {
                        UsageRow(num: "1", icon: "app.badge", text: "AI KeyChain を常時起動（メニューバーに常駐）")
                        UsageRow(num: "2", icon: "terminal", text: "ターミナルで claude などをそのまま使う")
                        UsageRow(num: "3", icon: "shield.checkered", text: "プロキシが自動で認証 — キーは env に出ない")
                    }
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 40)

                    Label("接続不能時はメニューバー → Recovery Guide で復旧できます",
                          systemImage: "lifepreserver")
                        .font(AppFonts.caption)
                        .foregroundStyle(.orange)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        UsageRow(num: "1", icon: "key.fill", text: "API キーを Keychain に登録")
                        UsageRow(num: "2", icon: "terminal", text: ".zshrc の export で環境変数に設定")
                        UsageRow(num: "3", icon: "bolt.fill", text: "ターミナルで AI ツールをそのまま使う")
                    }
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 40)

                    Label("メニューバーからいつでもモードを変更できます",
                          systemImage: "menubar.rectangle")
                        .font(AppFonts.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 30)
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - Helper Components

private struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let desc: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(color, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(desc).font(AppFonts.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct FlowBox: View {
    let label: String
    let detail: String
    let color: Color
    var icon: String = ""

    var body: some View {
        HStack(spacing: 10) {
            if !icon.isEmpty {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(color)
                    .frame(width: 24)
            }
            VStack(spacing: 2) {
                Text(label).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.25)))
    }
}

private struct FlowArrow: View {
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "arrow.down")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppColors.aiPurple.opacity(0.6))
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
    }
}

private struct UsageRow: View {
    let num: String
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppColors.aiPurple)
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
            }
            Text(text)
                .font(.system(size: 13))
        }
    }
}
