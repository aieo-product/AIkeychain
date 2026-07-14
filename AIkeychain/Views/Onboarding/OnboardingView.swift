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
                case .language:
                    LanguageSelectStepView()
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
                        Label(L10n.t("back"), systemImage: "chevron.left")
                    }
                }

                Spacer()

                if viewModel.currentStep.canSkip {
                    Button(L10n.t("skip")) {
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
                        Label(L10n.t("get_started"), systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button {
                        withAnimation(AppAnimations.transition) {
                            viewModel.next()
                        }
                    } label: {
                        Label(L10n.t("next"), systemImage: "chevron.right")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 660, height: 640)
    }
}

// MARK: - Language Select

struct LanguageSelectStepView: View {
    @State private var selected: AppLanguage = AppState.shared.appLanguage

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 30)

            Image(systemName: "globe")
                .font(.system(size: 56))
                .foregroundStyle(AppColors.accentGradient)

            Text(L10n.t("language_title"))
                .font(AppFonts.pageTitle)

            Text(L10n.t("language_subtitle"))
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 20) {
                ForEach(AppLanguage.allCases) { lang in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selected = lang
                            AppState.shared.appLanguage = lang
                        }
                    } label: {
                        VStack(spacing: 12) {
                            Text(lang.flag)
                                .font(.system(size: 48))
                            Text(lang.displayName)
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .frame(width: 160, height: 130)
                        .background(
                            selected == lang ? AppColors.aiPurple.opacity(0.08) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 16)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(selected == lang ? AppColors.aiPurple : Color.gray.opacity(0.15),
                                        lineWidth: selected == lang ? 2.5 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 30)
        }
        .padding(.horizontal)
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

                Text(L10n.t("welcome_title"))
                    .font(AppFonts.pageTitle)

                Text(L10n.t("welcome_subtitle"))
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 14) {
                    FeatureRow(icon: "lock.shield", color: AppColors.aiPurple,
                               title: L10n.t("welcome_feature1_title"),
                               desc: L10n.t("welcome_feature1_desc"))
                    FeatureRow(icon: "eye.slash", color: AppColors.cloudBlue,
                               title: L10n.t("welcome_feature2_title"),
                               desc: L10n.t("welcome_feature2_desc"))
                    FeatureRow(icon: "arrow.triangle.2.circlepath", color: AppColors.commGreen,
                               title: L10n.t("welcome_feature3_title"),
                               desc: L10n.t("welcome_feature3_desc"))
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
    @State private var animateCards = false
    @State private var showDiagram = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Spacer(minLength: 12)

                Text(L10n.t("mode_select_title"))
                    .font(AppFonts.sectionTitle)

                Text(L10n.t("mode_select_subtitle"))
                    .font(AppFonts.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                // Mode comparison cards — 3 columns
                HStack(spacing: 10) {
                    // Standard card
                    OnboardingModeCard(
                        isSelected: selectedMode == .standard,
                        icon: "key.fill",
                        color: AppColors.commGreen,
                        title: "Standard",
                        subtitle: L10n.t("mode_standard_subtitle"),
                        items: [
                            ("checkmark.circle", L10n.t("mode_standard_pro"), AppColors.commGreen),
                            ("exclamationmark.triangle", L10n.t("mode_standard_con"), .orange),
                        ]
                    ) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            selectedMode = .standard
                            AppState.shared.switchMode(to: .standard)
                        }
                    }

                    // Secret Reference card
                    OnboardingModeCard(
                        isSelected: selectedMode == .secretReference,
                        icon: "link.badge.plus",
                        color: AppColors.cloudBlue,
                        title: "Secret Ref",
                        subtitle: L10n.t("mode_secretref_subtitle"),
                        items: [
                            ("checkmark.circle", L10n.t("mode_secretref_pro"), AppColors.cloudBlue),
                            ("exclamationmark.triangle", L10n.t("mode_secretref_con"), .orange),
                        ]
                    ) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            selectedMode = .secretReference
                            AppState.shared.switchMode(to: .secretReference)
                        }
                    }

                    // Proxy card
                    OnboardingModeCard(
                        isSelected: selectedMode == .proxy,
                        icon: "shield.checkered",
                        color: AppColors.aiPurple,
                        title: "Proxy",
                        subtitle: L10n.t("mode_proxy_subtitle"),
                        items: [
                            ("checkmark.circle", L10n.t("mode_proxy_pro"), AppColors.aiPurple),
                            ("exclamationmark.triangle", L10n.t("mode_proxy_con"), .orange),
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
                }
                .scaleEffect(animateCards ? 1.0 : 0.9)
                .opacity(animateCards ? 1.0 : 0)
                .padding(.horizontal, 16)

                // Animated flow diagram
                if showDiagram {
                    VStack(spacing: 0) {
                        switch selectedMode {
                        case .standard:
                            FlowBox(label: L10n.t("flow_terminal"), detail: L10n.t("flow_standard_detail"), color: AppColors.commGreen, icon: "terminal")
                            FlowArrow(label: L10n.t("flow_standard_arrow"))
                            FlowBox(label: L10n.t("flow_api_server"), detail: "api.anthropic.com", color: AppColors.cloudBlue, icon: "cloud.fill")
                        case .secretReference:
                            FlowBox(label: L10n.t("flow_terminal"), detail: L10n.t("flow_secretref_detail"), color: AppColors.cloudBlue, icon: "terminal")
                            FlowArrow(label: L10n.t("flow_secretref_arrow1"))
                            FlowBox(label: L10n.t("flow_secretref_child"), detail: L10n.t("flow_secretref_child_detail"), color: AppColors.commGreen, icon: "gearshape")
                            FlowArrow(label: L10n.t("flow_secretref_arrow2"))
                            FlowBox(label: L10n.t("flow_api_server"), detail: "api.anthropic.com", color: AppColors.cloudBlue, icon: "cloud.fill")
                        case .proxy:
                            FlowBox(label: L10n.t("flow_terminal"), detail: L10n.t("flow_proxy_detail"), color: AppColors.aiPurple, icon: "terminal")
                            FlowArrow(label: L10n.t("flow_proxy_arrow1"))
                            FlowBox(label: L10n.t("flow_proxy_box"), detail: L10n.t("flow_proxy_box_detail"), color: AppColors.cloudBlue, icon: "key.fill")
                            FlowArrow(label: L10n.t("flow_proxy_arrow2"))
                            FlowBox(label: L10n.t("flow_api_server"), detail: "api.anthropic.com", color: AppColors.commGreen, icon: "cloud.fill")
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
                    Label(L10n.t("mode_proxy_warning"),
                          systemImage: "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 30)
                        .transition(.opacity)
                }

                if selectedMode == .secretReference {
                    Label(L10n.t("mode_secretref_info"),
                          systemImage: "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.cloudBlue)
                        .padding(.horizontal, 30)
                        .transition(.opacity)
                }

                Spacer(minLength: 12)
            }
            .padding(.horizontal)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.15)) {
                animateCards = true
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

                Text(L10n.t("register_title"))
                    .font(AppFonts.sectionTitle)

                Text(L10n.t("register_subtitle"))
                    .font(AppFonts.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                // Quick status
                VStack(spacing: 10) {
                    // 発見用 .cliAdded は CLI キーがある時だけ出す（オンボーディング初期は常に空 / Codex #4）
                    ForEach(KeyCategory.allCases.filter { $0 != .cliAdded || keyListVM.builtinCategoryCount(for: $0) > 0 }) { category in
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

                Label(L10n.t("register_tip"),
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

                Text(L10n.t("shell_title"))
                    .font(AppFonts.sectionTitle)

                Text(L10n.t("shell_subtitle"))
                    .font(AppFonts.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                // Port selector
                HStack(spacing: 8) {
                    Text(L10n.t("shell_port"))
                        .font(.system(size: 13, weight: .medium))
                    TextField("Port", text: $portText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .onSubmit { applyPort() }
                    Button(L10n.t("apply")) { applyPort() }
                        .controlSize(.small)
                    Text(L10n.t("shell_default_port").replacingOccurrences(of: "%@", with: "\(AppState.defaultPort)"))
                        .font(AppFonts.caption)
                        .foregroundStyle(.tertiary)
                }

                // Preview
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.t("shell_zshrc_label"))
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
                    Label(L10n.t("shell_note1"), systemImage: "checkmark.shield")
                    Label(L10n.t("shell_note2"), systemImage: "xmark.shield")
                    Label(L10n.t("shell_note3"), systemImage: "shield.checkered")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

                if isConfigured {
                    Label(L10n.t("shell_configured"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(AppColors.configured)
                        .font(.system(size: 14, weight: .medium))
                } else {
                    Button(L10n.t("shell_enable_proxy")) {
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

                Label(L10n.t("shell_key_safe"),
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
            errorMessage = L10n.t("shell_port_error")
            return
        }
        errorMessage = nil
        AppState.shared.changePort(to: value)
    }
}

struct CompletionStepView: View {
    private var mode: KeyManagementMode { AppState.shared.keyManagementMode }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 30)

                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(AppColors.configured)

                Text(L10n.t("completion_title"))
                    .font(AppFonts.pageTitle)

                Text(completionMessage)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)

                switch mode {
                case .standard:
                    VStack(alignment: .leading, spacing: 14) {
                        UsageRow(num: "1", icon: "key.fill", text: L10n.t("completion_standard_step1"))
                        UsageRow(num: "2", icon: "terminal", text: L10n.t("completion_standard_step2"))
                        UsageRow(num: "3", icon: "bolt.fill", text: L10n.t("completion_standard_step3"))
                    }
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 40)

                    Label(L10n.t("completion_mode_change_hint"),
                          systemImage: "menubar.rectangle")
                        .font(AppFonts.caption)
                        .foregroundStyle(.tertiary)

                case .secretReference:
                    VStack(alignment: .leading, spacing: 14) {
                        UsageRow(num: "1", icon: "key.fill", text: L10n.t("completion_secretref_step1"))
                        UsageRow(num: "2", icon: "terminal", text: L10n.t("completion_secretref_step2"))
                        UsageRow(num: "3", icon: "play.fill", text: L10n.t("completion_secretref_step3"))
                    }
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 40)

                    Label(L10n.t("completion_secretref_warning"),
                          systemImage: "exclamationmark.triangle")
                        .font(AppFonts.caption)
                        .foregroundStyle(.orange)

                case .proxy:
                    VStack(alignment: .leading, spacing: 14) {
                        UsageRow(num: "1", icon: "app.badge", text: L10n.t("completion_proxy_step1"))
                        UsageRow(num: "2", icon: "terminal", text: L10n.t("completion_proxy_step2"))
                        UsageRow(num: "3", icon: "shield.checkered", text: L10n.t("completion_proxy_step3"))
                    }
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 40)

                    Label(L10n.t("completion_proxy_hint"),
                          systemImage: "lifepreserver")
                        .font(AppFonts.caption)
                        .foregroundStyle(.orange)
                }

                Spacer(minLength: 30)
            }
            .padding(.horizontal)
        }
    }

    private var completionMessage: String {
        switch mode {
        case .standard: L10n.t("completion_standard")
        case .secretReference: L10n.t("completion_secretref")
        case .proxy: L10n.t("completion_proxy")
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
