import SwiftUI

/// env インポート 4ステップウィザード
/// Step 1: env 取得ガイド（コマンド案内）
/// Step 2: ペースト & スキャン結果（レコメンド付き）
/// Step 3: Keychain インポートプレビュー
/// Step 4: 実行結果
struct EnvImportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentStep = 0
    @State private var inputText = ""
    @State private var parsedEntries: [EnvEntry] = []
    @State private var importResult: ImportResult?
    @State private var removeFromZshrc = true

    var onImport: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 24))
                    .foregroundStyle(AppColors.accentGradient)
                VStack(alignment: .leading) {
                    Text("Import Keys")
                        .font(AppFonts.sectionTitle)
                    Text(stepSubtitle)
                        .font(AppFonts.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            // Step indicator
            HStack(spacing: 0) {
                ForEach(0..<4) { step in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(step <= currentStep ? AppColors.aiPurple : Color.gray.opacity(0.2))
                            .frame(width: 24, height: 24)
                            .overlay(
                                Text("\(step + 1)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(step <= currentStep ? .white : .secondary)
                            )
                        Text(stepNames[step])
                            .font(.system(size: 10, weight: step == currentStep ? .semibold : .regular))
                            .foregroundStyle(step == currentStep ? .primary : .secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    if step < 3 {
                        Rectangle()
                            .fill(step < currentStep ? AppColors.aiPurple : Color.gray.opacity(0.2))
                            .frame(height: 2)
                            .frame(maxWidth: 20)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            Divider()

            // Content
            Group {
                switch currentStep {
                case 0: step1GetEnv
                case 1: step2PasteAndScan
                case 2: step3Preview
                case 3: step4Result
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Navigation
            HStack {
                if currentStep > 0 && currentStep < 3 {
                    Button("Back") {
                        withAnimation { currentStep -= 1 }
                    }
                }
                Spacer()
                switch currentStep {
                case 0:
                    Button("I have the env copied") {
                        withAnimation { currentStep = 1 }
                    }
                    .buttonStyle(.borderedProminent)
                case 1:
                    Button("Review \(parsedEntries.filter(\.enabled).count) Keys") {
                        withAnimation { currentStep = 2 }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(parsedEntries.filter(\.enabled).isEmpty)
                case 2:
                    Button("Import to Keychain") {
                        performImport()
                        withAnimation { currentStep = 3 }
                    }
                    .buttonStyle(.borderedProminent)
                case 3:
                    Button("Done") {
                        onImport()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                default:
                    EmptyView()
                }
            }
            .padding(16)
        }
        .frame(width: 620, height: 580)
    }

    private let stepNames = ["Get env", "Scan", "Preview", "Result"]

    private var stepSubtitle: String {
        switch currentStep {
        case 0: L10n.s(ja: "ターミナルで env を取得", en: "Get env from terminal")
        case 1: L10n.s(ja: "貼り付けてスキャン", en: "Paste and scan")
        case 2: L10n.s(ja: "インポート内容を確認", en: "Review import contents")
        case 3: L10n.s(ja: "完了", en: "Done")
        default: ""
        }
    }

    // MARK: - Step 1: Get env

    private var step1GetEnv: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Spacer(minLength: 10)

                Text(L10n.s(ja: "ターミナルで以下のコマンドを実行し、結果をコピーしてください。", en: "Run the following command in Terminal and copy the result."))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                CommandBlock(
                    title: L10n.s(ja: "API キー・トークンを抽出", en: "Extract API keys and tokens"),
                    command: "env | grep -E 'API_KEY|TOKEN|SECRET|ACCOUNT_ID|AUTH_KEY'"
                )

                CommandBlock(
                    title: L10n.s(ja: "全 env を取得（上記で不足の場合）", en: "Get all env (if the above is insufficient)"),
                    command: "env"
                )

                CommandBlock(
                    title: L10n.s(ja: ".zshrc の export 行を取得", en: "Get export lines from .zshrc"),
                    command: "grep '^export' ~/.zshrc"
                )

                if let envPath = findLocalEnvFile() {
                    CommandBlock(
                        title: L10n.s(ja: ".env ファイルの内容を取得", en: "Get .env file contents"),
                        command: "cat \(envPath)"
                    )
                }

                Label(L10n.s(ja: "コマンドの実行結果をコピーしたら「I have the env copied」をクリック", en: "After copying the command output, click \"I have the env copied\""),
                      systemImage: "arrow.right.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.aiPurple)

                Spacer(minLength: 10)
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Step 2: Paste and Scan

    private var step2PasteAndScan: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.s(ja: "env の内容を貼り付けてください:", en: "Paste the env contents:"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                TextEditor(text: $inputText)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(height: 100)
                    .border(Color.gray.opacity(0.2))
                    .onChange(of: inputText) {
                        parsedEntries = EnvParser.parse(inputText)
                    }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            if parsedEntries.isEmpty && !inputText.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(L10n.s(ja: "有効な env 変数が見つかりません", en: "No valid env variables found"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else if !parsedEntries.isEmpty {
                HStack {
                    Text("\(parsedEntries.count) keys found")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    let detected = parsedEntries.filter { $0.matchedService != nil }.count
                    Text("\(detected) auto-detected")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                List {
                    // Proxy recommended
                    let proxyKeys = parsedEntries.filter { $0.recommendation == .proxyRecommended }
                    if !proxyKeys.isEmpty {
                        Section {
                            ForEach($parsedEntries) { $entry in
                                if entry.recommendation == .proxyRecommended {
                                    EnvEntryRow(entry: $entry)
                                }
                            }
                        } header: {
                            Label(L10n.s(ja: "Proxy 移行推奨 — env から API キーが丸見えです", en: "Proxy migration recommended — API keys are exposed in env"), systemImage: "exclamationmark.shield")
                                .foregroundStyle(.red)
                                .font(.system(size: 11))
                        }
                    }

                    // Check usage
                    let checkKeys = parsedEntries.filter { $0.recommendation == .checkUsage }
                    if !checkKeys.isEmpty {
                        Section {
                            ForEach($parsedEntries) { $entry in
                                if entry.recommendation == .checkUsage {
                                    EnvEntryRow(entry: $entry)
                                }
                            }
                        } header: {
                            Label(L10n.s(ja: "利用状況を確認", en: "Check usage"), systemImage: "questionmark.circle")
                                .foregroundStyle(.orange)
                                .font(.system(size: 11))
                        }
                    }

                    // Keep as is
                    let keepKeys = parsedEntries.filter { $0.recommendation == .keepAsIs }
                    if !keepKeys.isEmpty {
                        Section {
                            ForEach($parsedEntries) { $entry in
                                if entry.recommendation == .keepAsIs {
                                    EnvEntryRow(entry: $entry)
                                }
                            }
                        } header: {
                            Label(L10n.s(ja: "Keychain 保存可能", en: "Ready to save to Keychain"), systemImage: "checkmark.circle")
                                .foregroundStyle(.green)
                                .font(.system(size: 11))
                        }
                    }

                    // Unknown
                    let unknownKeys = parsedEntries.filter { $0.recommendation == nil }
                    if !unknownKeys.isEmpty {
                        Section {
                            ForEach($parsedEntries) { $entry in
                                if entry.recommendation == nil {
                                    EnvEntryRow(entry: $entry)
                                }
                            }
                        } header: {
                            Label(L10n.s(ja: "その他", en: "Other"), systemImage: "key")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 11))
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    // MARK: - Step 3: Preview

    private var step3Preview: some View {
        let selected = parsedEntries.filter(\.enabled)

        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Spacer(minLength: 10)

                Text(L10n.s(ja: "以下のキーを Keychain に保存します", en: "The following keys will be saved to Keychain"))
                    .font(.system(size: 14, weight: .medium))

                VStack(spacing: 1) {
                    ForEach(selected) { entry in
                        HStack(spacing: 10) {
                            if let service = entry.matchedService {
                                Image(systemName: service.systemImage)
                                    .foregroundStyle(service.category.color)
                                    .frame(width: 20)
                            } else {
                                Image(systemName: "key")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)
                            }

                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.matchedService?.displayName ?? entry.key)
                                    .font(.system(size: 12, weight: .medium))
                                Text(entry.key)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }

                            Spacer()

                            if KeychainService.shared.exists(for: entry.matchedService?.envVarName ?? entry.key) {
                                Label("Overwrite", systemImage: "exclamationmark.triangle")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.orange)
                            } else {
                                Label("New", systemImage: "plus.circle")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.green)
                            }

                            Text(SecretMask.mask(entry.value))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .frame(width: 80, alignment: .trailing)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

                Divider()

                // .zshrc cleanup option
                Toggle(isOn: $removeFromZshrc) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.s(ja: ".zshrc から該当する export 行を削除する", en: "Remove matching export lines from .zshrc"))
                            .font(.system(size: 12, weight: .medium))
                        Text(L10n.s(ja: "Keychain に移行後、env への露出を防ぎます。バックアップが自動作成されます。", en: "Prevents env exposure after migrating to Keychain. A backup is created automatically."))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 6) {
                    Label(L10n.s(ja: "保存先: macOS Keychain (com.aieo.aikeychain)", en: "Destination: macOS Keychain (com.aieo.aikeychain)"), systemImage: "lock.shield")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    if AppState.shared.isProxyMode {
                        let aiCount = selected.filter { isAIKey($0.key) }.count
                        if aiCount > 0 {
                            Label(L10n.s(ja: "AI API キー \(aiCount)件: Proxy 経由で env に露出せず利用可能", en: "\(aiCount) AI API key(s): available via Proxy without env exposure"),
                                  systemImage: "shield.checkered")
                                .font(.system(size: 11))
                                .foregroundStyle(AppColors.aiPurple)
                        }
                    }
                }

                Spacer(minLength: 10)
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Step 4: Result

    private var step4Result: some View {
        VStack(spacing: 20) {
            Spacer()

            if let result = importResult {
                let clean = result.failed == 0 && result.cliManaged.isEmpty
                Image(systemName: clean ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(clean ? AppColors.configured : .orange)

                Text(clean ? "Import Complete!" : "Partially Imported")
                    .font(.system(size: 18, weight: .semibold))

                VStack(spacing: 8) {
                    ResultRow(icon: "checkmark.circle.fill", color: .green,
                              text: "\(result.saved) keys saved to Keychain")

                    if result.removedFromZshrc > 0 {
                        ResultRow(icon: "trash.circle.fill", color: AppColors.aiPurple,
                                  text: "\(result.removedFromZshrc) export lines removed from .zshrc")
                    }

                    if result.skipped > 0 {
                        ResultRow(icon: "minus.circle", color: .secondary,
                                  text: "\(result.skipped) keys skipped")
                    }
                    if result.failed > 0 {
                        ResultRow(icon: "xmark.circle.fill", color: .red,
                                  text: "\(result.failed) keys failed")
                    }
                    if !result.cliManaged.isEmpty {
                        ResultRow(icon: "terminal.fill", color: .orange,
                                  text: L10n.s(
                                    ja: "\(result.cliManaged.count) 件は akc CLI 管理のため未更新。ターミナルで更新してください: akc set \(result.cliManaged.joined(separator: " / akc set "))",
                                    en: "\(result.cliManaged.count) key(s) are managed by the akc CLI and were not updated. Update them in a terminal: akc set \(result.cliManaged.joined(separator: " / akc set "))"))
                    }
                }
                .padding(.horizontal, 40)

                if result.removedFromZshrc > 0 {
                    VStack(spacing: 4) {
                        Label("Backup: ~/.zshrc.aikeychain.bak", systemImage: "doc.badge.clock")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Label(L10n.s(ja: "新しいターミナルを開くと反映されます", en: "Changes will take effect in a new terminal session"), systemImage: "terminal")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                } else if result.saved > 0 {
                    Label(L10n.s(ja: "新しいターミナルを開くと反映されます", en: "Changes will take effect in a new terminal session"), systemImage: "terminal")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
    }

    // MARK: - Actions

    private func performImport() {
        let selected = parsedEntries.filter(\.enabled)
        var saved = 0
        var failed = 0
        var removedFromZshrc = 0
        var savedKeys: [String] = []
        var cliManagedKeys: [String] = []

        for entry in selected {
            let account = entry.matchedService?.envVarName ?? entry.key
            do {
                try KeychainService.shared.save(value: entry.value, for: account)
                saved += 1
                savedKeys.append(account)
            } catch KeychainError.cliManaged {
                // #177: このキーは akc CLI 管理（security 所有）。GUI から上書きすると
                // 毒化するため save() が fail-closed した。古い値のまま黙って放置せず、
                // 「akc set で更新して」と明示する。
                cliManagedKeys.append(account)
            } catch {
                failed += 1
            }
        }

        // .zshrc から export 行を削除
        if removeFromZshrc && !savedKeys.isEmpty {
            do {
                try SetupManager.removeExportLines(envVarNames: savedKeys)
                removedFromZshrc = savedKeys.count
            } catch {
                // Keychain 保存は成功、.zshrc 削除は失敗
            }
        }

        let skipped = parsedEntries.count - selected.count
        importResult = ImportResult(saved: saved, skipped: skipped, failed: failed,
                                    removedFromZshrc: removedFromZshrc, cliManaged: cliManagedKeys)
    }

    private func isAIKey(_ key: String) -> Bool {
        let aiKeys = ["ANTHROPIC_API_KEY", "OPENAI_API_KEY", "XAI_API_KEY", "HIGGSFIELD_API_KEY"]
        return aiKeys.contains(key)
    }

    private func findLocalEnvFile() -> String? {
        let candidates = [".env", ".env.local", "local.env"]
        let cwd = FileManager.default.currentDirectoryPath
        for name in candidates {
            if FileManager.default.fileExists(atPath: cwd + "/" + name) {
                return name
            }
        }
        return nil
    }
}

// MARK: - Components

private struct CommandBlock: View {
    let title: String
    let command: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            HStack {
                Text(command)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Copy")
            }
            .padding(10)
            .background(Color(.textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct EnvEntryRow: View {
    @Binding var entry: EnvEntry

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: $entry.enabled)
                .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.key)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))

                    if let service = entry.matchedService {
                        Text(service.displayName)
                            .font(.system(size: 9))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(service.category.color, in: Capsule())
                    } else if let guess = entry.guessedCategory {
                        Text(guess)
                            .font(.system(size: 9))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.gray, in: Capsule())
                    }
                }

                Text(SecretMask.mask(entry.value))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if KeychainService.shared.exists(for: entry.matchedService?.envVarName ?? entry.key) {
                Text("Exists")
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 1)
    }
}

private struct ResultRow: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(text)
                .font(.system(size: 13))
        }
    }
}

// MARK: - Models

private struct ImportResult {
    let saved: Int
    let skipped: Int
    let failed: Int
    let removedFromZshrc: Int
    /// #177: akc CLI 管理（security 所有）で GUI から上書きできなかったキー。
    /// 古い値のまま残るため `akc set <KEY>` での更新を案内する。
    var cliManaged: [String] = []
}

struct EnvEntry: Identifiable {
    let id = UUID()
    let key: String
    let value: String
    var enabled: Bool
    var matchedService: ServiceType?
    var guessedCategory: String?
    var recommendation: EnvRecommendation?
}

enum EnvRecommendation {
    case proxyRecommended
    case checkUsage
    case keepAsIs
}

// MARK: - Parser

enum EnvParser {
    static func parse(_ text: String) -> [EnvEntry] {
        text.components(separatedBy: .newlines)
            .compactMap { parseLine($0) }
    }

    private static func parseLine(_ line: String) -> EnvEntry? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }

        var working = trimmed
        if working.hasPrefix("export ") {
            working = String(working.dropFirst(7))
        }

        guard let eqIndex = working.firstIndex(of: "=") else { return nil }
        let key = String(working[working.startIndex..<eqIndex]).trimmingCharacters(in: .whitespaces)
        var value = String(working[working.index(after: eqIndex)...]).trimmingCharacters(in: .whitespaces)

        if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
           (value.hasPrefix("'") && value.hasSuffix("'")) {
            value = String(value.dropFirst().dropLast())
        }

        // Skip shell expansions
        if value.contains("$(") || value.contains("`") || value.hasPrefix("$") { return nil }

        // Skip system vars
        let systemVars = ["PATH", "HOME", "USER", "SHELL", "LANG", "TERM", "TMPDIR",
                          "LOGNAME", "PWD", "OLDPWD", "SHLVL", "COLORTERM",
                          "BUN_INSTALL", "HOMEBREW_PREFIX", "HOMEBREW_CELLAR",
                          "HOMEBREW_REPOSITORY", "INFOPATH", "MANPATH", "XDG_DATA_DIRS",
                          "COMMAND_MODE", "SECURITYSESSIONID", "SSH_AUTH_SOCK",
                          "LaunchInstanceID", "XPC_FLAGS", "XPC_SERVICE_NAME",
                          "VIPSHOME", "COREPACK_ENABLE_AUTO_PIN", "GIT_EDITOR",
                          "NoDefaultCurrentDirectoryInExePath", "OSLogRateLimit"]
        if systemVars.contains(key) { return nil }
        if key.hasPrefix("CMUX_") || key.hasPrefix("GHOSTTY_") || key.hasPrefix("TERM_") { return nil }
        if key.hasPrefix("CLAUDE_CODE") || key.hasPrefix("CLAUDECODE") || key.hasPrefix("OTEL_") { return nil }
        if key.hasPrefix("__CF") || key == "_" { return nil }

        guard !key.isEmpty, !value.isEmpty else { return nil }

        // 安全なシェル変数名パターンに一致しないキーはインポート対象から除外する
        // （不正な文字列が Keychain に書き込まれる/後続処理でシェル展開されるのを防ぐ）。
        guard EnvVarName.isValid(key) else { return nil }

        let matched = ServiceType.allCases.first { $0.envVarName == key }
        let guess = matched == nil ? guessCategory(key: key) : nil
        let recommendation = classify(key: key, matched: matched)

        return EnvEntry(
            key: key, value: value,
            enabled: matched != nil,
            matchedService: matched,
            guessedCategory: guess,
            recommendation: recommendation
        )
    }

    private static func classify(key: String, matched: ServiceType?) -> EnvRecommendation? {
        let aiKeys = ["ANTHROPIC_API_KEY", "OPENAI_API_KEY", "XAI_API_KEY", "HIGGSFIELD_API_KEY"]
        if aiKeys.contains(key) { return .proxyRecommended }

        let lower = key.lowercased()
        if lower.contains("hugging") || lower.contains("replicate") || lower.contains("cohere") ||
           lower.contains("mistral") || lower.contains("groq") || lower.contains("deepseek") {
            return .proxyRecommended
        }

        let botKeys = ["DISCORD_TOKEN", "SLACK_APP_TOKEN", "SLACK_BOT_TOKEN"]
        if botKeys.contains(key) { return .checkUsage }

        if matched != nil { return .keepAsIs }

        if lower.contains("api_key") || lower.contains("secret") || lower.contains("token") {
            return .checkUsage
        }

        return nil
    }

    static func guessCategory(key: String) -> String? {
        let lower = key.lowercased()
        if lower.contains("openai") || lower.contains("gpt") { return "OpenAI" }
        if lower.contains("anthropic") || lower.contains("claude") { return "Anthropic" }
        if lower.contains("gemini") || lower.contains("google_ai") { return "Google AI" }
        if lower.contains("hugging") || lower.contains("hf_") { return "Hugging Face" }
        if lower.contains("replicate") { return "Replicate" }
        if lower.contains("cohere") { return "Cohere" }
        if lower.contains("mistral") { return "Mistral" }
        if lower.contains("groq") { return "Groq" }
        if lower.contains("deepseek") { return "DeepSeek" }
        if lower.contains("aws") || lower.contains("amazon") { return "AWS" }
        if lower.contains("azure") { return "Azure" }
        if lower.contains("cloudflare") { return "Cloudflare" }
        if lower.contains("vercel") { return "Vercel" }
        if lower.contains("supabase") { return "Supabase" }
        if lower.contains("github") || lower.contains("gh_") { return "GitHub" }
        if lower.contains("gitlab") || lower.contains("gl_") { return "GitLab" }
        if lower.contains("slack") { return "Slack" }
        if lower.contains("discord") { return "Discord" }
        if lower.contains("stripe") { return "Stripe" }
        if lower.contains("sentry") { return "Sentry" }
        if lower.contains("api_key") || lower.contains("apikey") { return "API Key" }
        if lower.contains("token") { return "Token" }
        if lower.contains("secret") { return "Secret" }
        return nil
    }
}
