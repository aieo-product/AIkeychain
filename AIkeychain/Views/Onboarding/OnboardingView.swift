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
                case .proxyExplain:
                    ProxyExplainStepView()
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

struct ProxyExplainStepView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 20)

                Image(systemName: "shield.checkered")
                    .font(.system(size: 48))
                    .foregroundStyle(AppColors.cloudBlue)

                Text("How It Works")
                    .font(AppFonts.sectionTitle)

                Text("従来の方法では API キーが環境変数に露出します。\nAI KeyChain はプロキシ経由で安全に認証します。")
                    .font(AppFonts.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                // Flow diagram
                VStack(spacing: 0) {
                    FlowBox(label: "claude / AI ツール", detail: "env にキーなし — 安全", color: AppColors.aiPurple, icon: "brain")
                    FlowArrow(label: "HTTP リクエスト (認証ヘッダなし)")
                    FlowBox(label: "AI KeyChain Proxy", detail: "localhost:9999 — Keychain から読み取り", color: AppColors.cloudBlue, icon: "key.fill")
                    FlowArrow(label: "Authorization ヘッダを自動注入")
                    FlowBox(label: "API Server", detail: "api.anthropic.com — HTTPS 認証済み", color: AppColors.commGreen, icon: "cloud.fill")
                }
                .padding(.horizontal, 50)

                Label("AI プロセスの環境変数に API キーが一切露出しません",
                      systemImage: "checkmark.shield")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.configured)
                    .padding(.top, 4)

                Spacer(minLength: 20)
            }
            .padding(.horizontal)
        }
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
                            let total = keyListVM.categoryCount(for: category)
                            let configured = keyListVM.categoryConfiguredCount(for: category)
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

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 20)

                Image(systemName: "terminal")
                    .font(.system(size: 48))
                    .foregroundStyle(AppColors.gitOrange)

                Text("Connect Your Shell")
                    .font(AppFonts.sectionTitle)

                Text(".zshrc にプロキシ設定を追加して、\nターミナルからシームレスに使えるようにします。")
                    .font(AppFonts.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                // Preview
                VStack(alignment: .leading, spacing: 6) {
                    Text("~/.zshrc に追記される内容:")
                        .font(AppFonts.badge)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("export ANTHROPIC_BASE_URL=http://localhost:9999")
                        Text("export OPENAI_BASE_URL=http://localhost:9999")
                        Text("export XAI_BASE_URL=http://localhost:9999")
                    }
                    .font(AppFonts.code)
                    .foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 40)

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
}

struct CompletionStepView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 30)

                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(AppColors.configured)

                Text("Setup Complete!")
                    .font(AppFonts.pageTitle)

                Text("セキュアな AI 開発環境が整いました")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 14) {
                    UsageRow(num: "1", icon: "app.badge", text: "AI KeyChain アプリを起動（メニューバーに常駐）")
                    UsageRow(num: "2", icon: "terminal", text: "ターミナルで claude など AI ツールをそのまま使う")
                    UsageRow(num: "3", icon: "shield.checkered", text: "プロキシが自動で認証 — キーは env に出ない")
                }
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 40)

                Label("メニューバーの鍵アイコンからいつでもプロキシ状態を確認できます",
                      systemImage: "menubar.rectangle")
                    .font(AppFonts.caption)
                    .foregroundStyle(.tertiary)

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
