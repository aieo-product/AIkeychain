import SwiftUI
import CryptoKit
import UniformTypeIdentifiers

/// 公開鍵暗号方式によるキー転送画面
/// デバイス間のバックアップ・移行用途
struct ShareKeysView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0
    let keys: [APIKey]
    var onImport: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "lock.shield")
                    .font(.system(size: 24))
                    .foregroundStyle(AppColors.accentGradient)
                VStack(alignment: .leading) {
                    Text("Transfer Keys")
                        .font(AppFonts.sectionTitle)
                    Text(L10n.s(ja: "公開鍵暗号方式でデバイス間を安全に移行", en: "Securely transfer between devices using public key cryptography"))
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

            // Terms notice
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                Text(L10n.s(ja: "この機能はデバイス間の移行用です。個人 API キーの第三者への共有は各サービスの利用規約に違反する可能性があります。組織キーをご利用ください。", en: "This feature is for device-to-device migration. Sharing personal API keys with third parties may violate service terms of use. Please use organization keys."))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)

            Picker("", selection: $selectedTab) {
                Text("My Keys").tag(0)
                Text("Send").tag(1)
                Text("Receive").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            Divider()

            switch selectedTab {
            case 0: KeyPairManagementTab()
            case 1: SendTab(keys: keys)
            case 2: ReceiveTab(onImport: onImport)
            default: EmptyView()
            }
        }
        .frame(width: 560, height: 520)
    }
}

// MARK: - Key Pair Management Tab

private struct KeyPairManagementTab: View {
    @State private var hasKeyPair = KeyShareService.hasKeyPair()
    @State private var publicKeyDisplay: String = ""
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Spacer(minLength: 16)

                Image(systemName: "key.horizontal")
                    .font(.system(size: 40))
                    .foregroundStyle(AppColors.aiPurple)

                if hasKeyPair {
                    Label("Key Pair Ready", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(AppColors.configured)
                        .font(.system(size: 15, weight: .medium))

                    Text(L10n.s(ja: "公開鍵を共有相手に渡してください。", en: "Share your public key with the recipient."))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    if !publicKeyDisplay.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Your Public Key (fingerprint):")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text(publicKeyDisplay)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .padding(10)
                        .background(Color(.textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal, 40)
                    }

                    HStack(spacing: 12) {
                        Button("Export Public Key...") {
                            exportPublicKey()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Delete Key Pair", role: .destructive) {
                            KeyShareService.deleteKeyPair()
                            hasKeyPair = false
                            publicKeyDisplay = ""
                        }
                    }
                } else {
                    Text(L10n.s(ja: "キーペアがありません。\n共有を受けるにはまず鍵を生成してください。", en: "No key pair found.\nGenerate a key pair first to receive shared keys."))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Generate Key Pair") {
                        do {
                            let pubKey = try KeyShareService.generateKeyPair()
                            hasKeyPair = true
                            publicKeyDisplay = fingerprint(pubKey)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                // How it works
                VStack(alignment: .leading, spacing: 8) {
                    Text("How it works")
                        .font(.system(size: 12, weight: .semibold))
                    FlowStep(num: "1", text: L10n.s(ja: "移行先デバイスで鍵ペアを生成し、公開鍵 (.aikeychain-pub) を移行元に渡す", en: "Generate a key pair on the destination device and send the public key (.aikeychain-pub) to the source"))
                    FlowStep(num: "2", text: L10n.s(ja: "移行元デバイスで公開鍵を使いキーを暗号化し、.aikeychain ファイルを渡す", en: "Encrypt keys using the public key on the source device and send the .aikeychain file"))
                    FlowStep(num: "3", text: L10n.s(ja: "移行先デバイスで秘密鍵を使い復号し、Keychain に登録する", en: "Decrypt with the private key on the destination device and register in Keychain"))
                }
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 30)

                if let error = errorMessage {
                    Text(error).font(.system(size: 11)).foregroundStyle(.red)
                }

                Spacer(minLength: 16)
            }
        }
        .onAppear {
            if let pubKey = KeyShareService.getPublicKey() {
                publicKeyDisplay = fingerprint(pubKey)
            }
        }
    }

    private func exportPublicKey() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "aikeychain-pub") ?? .data]
        panel.nameFieldStringValue = "mykey.aikeychain-pub"
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try KeyShareService.exportPublicKey(to: url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func fingerprint(_ key: P256.KeyAgreement.PublicKey) -> String {
        let data = key.x963Representation
        let hash = SHA256.hash(data: data)
        return hash.prefix(8).map { String(format: "%02x", $0) }.joined(separator: ":")
    }
}

// MARK: - Send Tab

private struct SendTab: View {
    let keys: [APIKey]
    @State private var selectedKeys: Set<String> = [] // envVarName ベース
    @State private var recipientPublicKey: P256.KeyAgreement.PublicKey?
    @State private var recipientFingerprint = ""
    @State private var errorMessage: String?
    @State private var exported = false
    @State private var cachedValues: [String: String] = [:] // 一括取得キャッシュ
    @State private var isLoading = false

    private var configuredKeys: [APIKey] {
        keys.filter(\.isConfigured)
    }

    var body: some View {
        VStack(spacing: 0) {
            if recipientPublicKey == nil {
                // Step 1: Load recipient's public key
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "person.badge.key.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(AppColors.cloudBlue)
                    Text(L10n.s(ja: "移行先デバイスの公開鍵を読み込んでください", en: "Load the destination device's public key"))
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)

                    Button("Open .aikeychain-pub...") {
                        loadRecipientKey()
                    }
                    .buttonStyle(.borderedProminent)

                    if let error = errorMessage {
                        Text(error).font(.system(size: 11)).foregroundStyle(.red)
                    }
                    Spacer()
                }
            } else if cachedValues.isEmpty && !isLoading {
                // Step 2: Batch load keys (1回の承認で全キー取得)
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "key.viewfinder")
                        .font(.system(size: 40))
                        .foregroundStyle(AppColors.aiPurple)
                    Text(L10n.s(ja: "Keychain からキーを読み込みます", en: "Load keys from Keychain"))
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    Text(L10n.s(ja: "Keychain の承認ダイアログが表示されます。\n「常に許可」を選ぶと次回以降ダイアログが出ません。", en: "A Keychain authorization dialog will appear.\nChoose \"Always Allow\" to skip the dialog next time."))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)

                    Button("Load Keys from Keychain") {
                        batchLoadKeys()
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                }
            } else if isLoading {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView()
                    Text(L10n.s(ja: "Keychain からキーを読み込み中...", en: "Loading keys from Keychain..."))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                // Step 3: Select keys and encrypt
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("Target device: \(recipientFingerprint)", systemImage: "desktopcomputer")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Change") {
                            recipientPublicKey = nil
                            cachedValues = [:]
                            selectedKeys = []
                        }
                        .font(.system(size: 10))
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    HStack {
                        Text(L10n.s(ja: "転送するキーを選択:", en: "Select keys to transfer:"))
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Button("Select All") {
                            selectedKeys = Set(cachedValues.keys)
                        }
                        .font(.system(size: 11))
                        Button("Deselect All") {
                            selectedKeys = []
                        }
                        .font(.system(size: 11))
                    }
                    .padding(.horizontal, 16)
                }

                List {
                    ForEach(configuredKeys.filter { cachedValues[$0.envVarName] != nil }) { key in
                        HStack {
                            Toggle("", isOn: Binding(
                                get: { selectedKeys.contains(key.envVarName) },
                                set: { isOn in
                                    if isOn { selectedKeys.insert(key.envVarName) }
                                    else { selectedKeys.remove(key.envVarName) }
                                }
                            ))
                            .labelsHidden()

                            Image(systemName: key.systemImage)
                                .foregroundStyle(key.categoryColor)
                                .frame(width: 20)
                            VStack(alignment: .leading) {
                                Text(key.displayName)
                                    .font(.system(size: 12, weight: .medium))
                                Text(key.envVarName)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .listStyle(.inset)

                Divider()

                HStack {
                    Text("\(selectedKeys.count)/\(cachedValues.count) keys selected")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if exported {
                        Label("Exported!", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 12))
                    }
                    Button("Encrypt & Save...") {
                        encryptSelected()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedKeys.isEmpty)
                }
                .padding(12)
            }
        }
    }

    private func loadRecipientKey() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "aikeychain-pub") ?? .data]
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let key = try KeyShareService.importPublicKey(from: url)
                recipientPublicKey = key
                let hash = SHA256.hash(data: key.x963Representation)
                recipientFingerprint = hash.prefix(8).map { String(format: "%02x", $0) }.joined(separator: ":")
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// 全キーの値を一括取得（Keychain 承認は1回にまとめる）
    private func batchLoadKeys() {
        isLoading = true
        // バックグラウンドで全キーを一括読み込み
        DispatchQueue.global(qos: .userInitiated).async {
            var values: [String: String] = [:]
            for key in configuredKeys {
                if let value = try? KeychainService.shared.retrieve(for: key.envVarName),
                   !value.isEmpty {
                    values[key.envVarName] = value
                }
            }
            DispatchQueue.main.async {
                cachedValues = values
                selectedKeys = Set(values.keys) // デフォルト全選択
                isLoading = false
            }
        }
    }

    private func encryptSelected() {
        guard let pubKey = recipientPublicKey else { return }

        // キャッシュから値を取得（Keychain への再アクセスなし）
        let keyPairs: [(envVarName: String, value: String)] = selectedKeys.compactMap { name in
            guard let value = cachedValues[name] else { return nil }
            return (name, value)
        }

        guard !keyPairs.isEmpty else {
            errorMessage = "No key values found"
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "aikeychain") ?? .data]
        panel.nameFieldStringValue = "transfer-keys.aikeychain"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try KeyShareService.encryptAndExport(keys: keyPairs, recipientPublicKey: pubKey, to: url)
                exported = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Receive Tab

private struct ReceiveTab: View {
    var onImport: () -> Void = {}
    @State private var decryptedKeys: [(envVarName: String, value: String)] = []
    @State private var imported = false
    @State private var importCount = 0
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if decryptedKeys.isEmpty && !imported {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "lock.open.rotation")
                        .font(.system(size: 40))
                        .foregroundStyle(AppColors.commGreen)

                    if KeyShareService.hasKeyPair() {
                        Text(L10n.s(ja: "暗号化された .aikeychain ファイルを\n自分の秘密鍵で復号します", en: "Decrypt the encrypted .aikeychain file\nusing your private key"))
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        Button("Open .aikeychain...") {
                            decryptFile()
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Text(L10n.s(ja: "鍵ペアが必要です。\n「My Keys」タブで生成してください。", en: "A key pair is required.\nGenerate one in the \"My Keys\" tab."))
                            .font(.system(size: 14))
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                    }

                    if let error = errorMessage {
                        Text(error).font(.system(size: 11)).foregroundStyle(.red)
                    }
                    Spacer()
                }
            } else if !decryptedKeys.isEmpty && !imported {
                // Preview decrypted keys
                VStack(alignment: .leading, spacing: 4) {
                    Text("Decrypted \(decryptedKeys.count) keys:")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }

                List {
                    ForEach(decryptedKeys, id: \.envVarName) { entry in
                        HStack {
                            let service = ServiceType.allCases.first { $0.envVarName == entry.envVarName }
                            Image(systemName: service?.systemImage ?? "key")
                                .foregroundStyle(service?.category.color ?? .secondary)
                                .frame(width: 20)
                            VStack(alignment: .leading) {
                                Text(service?.displayName ?? entry.envVarName)
                                    .font(.system(size: 12, weight: .medium))
                                Text(entry.envVarName)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            if KeychainService.shared.exists(for: entry.envVarName) {
                                Text("Overwrite")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
                .listStyle(.inset)

                Divider()

                HStack {
                    Spacer()
                    Button("Import to Keychain") {
                        importDecrypted()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(12)
            } else {
                // Import complete
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(AppColors.configured)
                    Text("\(importCount) keys imported!")
                        .font(.system(size: 16, weight: .semibold))
                    Text(L10n.s(ja: "Keychain に保存されました", en: "Saved to Keychain"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)

                    Button {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Keychain Access.app"))
                    } label: {
                        Label("Open Keychain Access", systemImage: "lock.rectangle")
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }
            }
        }
    }

    private func decryptFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "aikeychain") ?? .data]
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            do {
                decryptedKeys = try KeyShareService.decryptAndImport(from: url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func importDecrypted() {
        var count = 0
        for entry in decryptedKeys {
            // 外部由来の .aikeychain ファイルの envVarName は信頼できない。
            // シェル export に不正な名前はスキップする（KeychainService.save 側でも
            // 弾かれるが、ここで明示的に skip して意図を明確化 / #116）。
            guard EnvVarName.isValid(entry.envVarName) else { continue }
            if let _ = try? KeychainService.shared.save(value: entry.value, for: entry.envVarName) {
                count += 1
            }
        }
        importCount = count
        imported = true
        onImport() // キーリストを更新
    }
}

// MARK: - Components

private struct FlowStep: View {
    let num: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(num)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(AppColors.aiPurple, in: Circle())
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}
