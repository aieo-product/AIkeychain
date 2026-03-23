import SwiftUI

struct OnboardingView: View {
    @State private var viewModel = OnboardingViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            ProgressView(value: viewModel.progress)
                .tint(AppColors.aiPurple)
                .padding(.horizontal)
                .padding(.top, 12)

            // Step indicator
            HStack(spacing: 8) {
                ForEach(OnboardingStep.allCases) { step in
                    Circle()
                        .fill(step.rawValue <= viewModel.currentStep.rawValue
                              ? AppColors.aiPurple : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 8)

            // Content
            TabView(selection: $viewModel.currentStep) {
                WelcomeStepView()
                    .tag(OnboardingStep.welcome)

                ProxyExplainStepView()
                    .tag(OnboardingStep.proxyExplain)

                RegisterKeysStepView()
                    .tag(OnboardingStep.registerKeys)

                SetupShellStepView()
                    .tag(OnboardingStep.setupShell)

                CompletionStepView()
                    .tag(OnboardingStep.completion)
            }
            .tabViewStyle(.automatic)

            Divider()

            // Navigation
            HStack {
                if viewModel.canGoBack {
                    Button("Back") {
                        withAnimation(AppAnimations.transition) {
                            viewModel.back()
                        }
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
                    Button("Get Started") {
                        viewModel.complete()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Next") {
                        withAnimation(AppAnimations.transition) {
                            viewModel.next()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
        }
        .frame(width: 600, height: 520)
    }
}

// MARK: - Step Views

struct WelcomeStepView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "key.fill")
                .font(.system(size: 64))
                .foregroundStyle(AppColors.accentGradient)

            Text("AI KeyChain")
                .font(AppFonts.pageTitle)

            Text("AI API キーをセキュアに管理する macOS アプリ")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
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
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 40)

            Spacer()
        }
    }
}

struct ProxyExplainStepView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "shield.checkered")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.cloudBlue)

            Text("How It Works")
                .font(AppFonts.sectionTitle)

            // Flow diagram
            VStack(spacing: 0) {
                FlowBox(label: "claude / AI ツール", detail: "env にキーなし", color: AppColors.aiPurple)
                FlowArrow(label: "HTTP リクエスト (認証なし)")
                FlowBox(label: "AI KeyChain Proxy", detail: "localhost:9999", color: AppColors.cloudBlue)
                FlowArrow(label: "Keychain から読み取り → ヘッダ注入")
                FlowBox(label: "api.anthropic.com", detail: "HTTPS + 認証済み", color: AppColors.commGreen)
            }
            .padding(.horizontal, 60)

            Text("AI プロセスの環境変数に API キーが一切露出しません")
                .font(AppFonts.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            Spacer()
        }
    }
}

struct RegisterKeysStepView: View {
    @State private var keyListVM = KeyListViewModel()

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

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
            VStack(spacing: 8) {
                ForEach(KeyCategory.allCases) { category in
                    HStack {
                        CategoryIcon(category: category, size: 24)
                        Text(category.rawValue)
                            .font(.system(size: 13))
                        Spacer()
                        let total = keyListVM.categoryCount(for: category)
                        let configured = keyListVM.categoryConfiguredCount(for: category)
                        Text("\(configured) / \(total)")
                            .font(AppFonts.badge)
                            .foregroundStyle(configured == total && total > 0
                                             ? AppColors.configured : .secondary)
                    }
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 60)

            Text("Tip: メイン画面でキーを右クリック → Edit で登録できます")
                .font(AppFonts.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
    }
}

struct SetupShellStepView: View {
    @State private var isConfigured = SetupManager.isConfigured()
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

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
            VStack(alignment: .leading, spacing: 4) {
                Text("~/.zshrc に追記される内容:")
                    .font(AppFonts.badge)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("export ANTHROPIC_BASE_URL=http://localhost:9999")
                    Text("export OPENAI_BASE_URL=http://localhost:9999")
                    Text("export XAI_BASE_URL=http://localhost:9999")
                }
                .font(AppFonts.code)
                .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(.textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 40)

            if isConfigured {
                Label("設定済み", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(AppColors.configured)
            } else {
                Button("Enable Secure Proxy") {
                    do {
                        try SetupManager.configure()
                        isConfigured = true
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .buttonStyle(.bordered)
            }

            if let error = errorMessage {
                Text(error)
                    .font(AppFonts.caption)
                    .foregroundStyle(.red)
            }

            Text("※ API キーの値は書き込まれません。安全です。")
                .font(AppFonts.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
    }
}

struct CompletionStepView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(AppColors.configured)

            Text("Setup Complete!")
                .font(AppFonts.pageTitle)

            Text("セキュアな AI 開発環境が整いました")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                UsageRow(step: "1", text: "AI KeyChain アプリを起動（メニューバーに常駐）")
                UsageRow(step: "2", text: "ターミナルで claude など AI ツールをそのまま使う")
                UsageRow(step: "3", text: "プロキシが自動で認証 — キーは env に出ない")
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 40)

            Text("メニューバーの 🔑 からいつでもプロキシ状態を確認できます")
                .font(AppFonts.caption)
                .foregroundStyle(.tertiary)

            Spacer()
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
                .font(.system(size: 20))
                .foregroundStyle(color)
                .frame(width: 32)
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

    var body: some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 13, weight: .medium))
            Text(detail).font(AppFonts.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.3)))
    }
}

private struct FlowArrow: View {
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "arrow.down")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

private struct UsageRow: View {
    let step: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Text(step)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(AppColors.aiPurple, in: Circle())
            Text(text)
                .font(.system(size: 13))
        }
    }
}
