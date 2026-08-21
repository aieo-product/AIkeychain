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
    @State private var showDeleteConfirm = false
    // 署名鍵が Secure Enclave 保護か（#127）。SE→software のサイレント降格も可視化する。
    @State private var signingIsSecureEnclave: Bool?

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

                    // 署名鍵の保護レベルバッジ（#127）
                    if let isSE = signingIsSecureEnclave {
                        Label(
                            isSE
                                ? L10n.s(ja: "署名鍵: Secure Enclave 保護", en: "Signing key: Secure Enclave protected")
                                : L10n.s(ja: "署名鍵: ソフトウェア鍵", en: "Signing key: software key"),
                            systemImage: isSE ? "cpu.fill" : "key.fill"
                        )
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(isSE ? AppColors.configured : .secondary)
                    }

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
                            showDeleteConfirm = true
                        }
                        .confirmationDialog(
                            L10n.s(ja: "鍵ペアを削除しますか？", en: "Delete key pair?"),
                            isPresented: $showDeleteConfirm,
                            titleVisibility: .visible
                        ) {
                            Button(L10n.s(ja: "削除する", en: "Delete"), role: .destructive) {
                                KeyShareService.deleteKeyPair()
                                hasKeyPair = false
                                publicKeyDisplay = ""
                                signingIsSecureEnclave = nil
                            }
                            Button(L10n.s(ja: "キャンセル", en: "Cancel"), role: .cancel) {}
                        } message: {
                            Text(L10n.s(
                                ja: "鍵共有鍵に加えて署名アイデンティティも破棄されます。再生成すると署名フィンガープリントが変わり、以前あなたの指紋を確認した相手は改めて照合し直す必要があります。",
                                en: "This also destroys your signing identity, not just the key-agreement key. Regenerating produces a NEW signing fingerprint, so anyone who previously verified your fingerprint must re-verify it."
                            ))
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
                            signingIsSecureEnclave = KeyShareService.isSigningKeySecureEnclave()
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
            signingIsSecureEnclave = KeyShareService.isSigningKeySecureEnclave()
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
    @State private var failedKeys: [String] = [] // 読み込み失敗（拒否/ACL 不一致等）キー (#161)
    @State private var isLoading = false
    // 署名フィンガープリントは Keychain I/O（初回は鍵生成）を伴うので body 内で毎回
    // 呼ばず、onAppear で一度だけ解決して state に持つ（finding 6）。
    @State private var ownSigningFingerprint: String?
    @State private var signingKeyError = false

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
                    Text(L10n.s(ja: "managed namespace のキーは承認ダイアログ無しで読み込まれます。", en: "Keys in the managed namespace load without an authorization dialog."))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)

                    if !failedKeys.isEmpty {
                        Text(L10n.s(ja: "前回 \(failedKeys.count) 件のキーを読み込めませんでした。", en: "\(failedKeys.count) key(s) could not be loaded last time."))
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                    }

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
                            failedKeys = []
                        }
                        .font(.system(size: 10))
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    if let ownFP = ownSigningFingerprint {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.s(ja: "あなたの署名フィンガープリント（受信者に帯域外で伝えてください）:", en: "Your signing fingerprint (share it out-of-band with the recipient):"))
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                            Text(ownFP)
                                .font(.system(size: 10, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color(.textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                        .padding(.horizontal, 16)
                    } else if signingKeyError {
                        Text(L10n.s(ja: "署名鍵を準備できませんでした（Keychain アクセスを確認してください）。", en: "Could not prepare the signing key (check Keychain access)."))
                            .font(.system(size: 9))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                    }

                    if !failedKeys.isEmpty {
                        // 取得に失敗したキーを無警告で落とさない (#161)。拒否 / ACL 不一致 /
                        // 空値のキーはここに列挙し、再試行できるようにする。
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Label(
                                    L10n.s(ja: "読み込めなかったキー: \(failedKeys.count) 件（エクスポートに含まれません）", en: "\(failedKeys.count) key(s) could not be loaded (excluded from export)"),
                                    systemImage: "exclamationmark.triangle.fill"
                                )
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.orange)
                                Spacer()
                                Button(L10n.s(ja: "再試行", en: "Retry")) {
                                    batchLoadKeys()
                                }
                                .font(.system(size: 10))
                            }
                            Text(failedKeys.joined(separator: ", "))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .lineLimit(3)
                        }
                        .padding(8)
                        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                        .padding(.horizontal, 16)
                    }

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
        .onAppear {
            // 署名鍵の解決（初回は生成）を一度だけ実行。失敗時はエラー行を出す。
            if let fp = KeyShareService.ownSigningFingerprint() {
                ownSigningFingerprint = fp
            } else {
                signingKeyError = true
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

    /// 全キーの値を一括取得。Keychain の承認（ACL）はアイテム単位のため、他プロセス
    /// 作成のアイテムはキーごとにダイアログが出る。取得に失敗したキーは無警告で
    /// 落とさず failedKeys に集めて UI に出す (#161)。
    private func batchLoadKeys() {
        isLoading = true
        // バックグラウンドで全キーを一括読み込み
        DispatchQueue.global(qos: .userInitiated).async {
            var values: [String: String] = [:]
            var failed: [String] = []
            for key in configuredKeys {
                do {
                    if let value = try SecurityCLIKeychainService.shared.retrieve(for: key.envVarName),
                       !value.isEmpty {
                        values[key.envVarName] = value
                    }
                    // nil/空値は「未登録 or 空」で再試行しても直らないため failed に
                    // 入れない（承認拒否と混同させない）。isConfigured 直後の読取なので
                    // 実際にはほぼ発生しない。
                } catch {
                    // 承認ダイアログの拒否 / ACL 不一致など再試行で直り得る失敗
                    failed.append(key.envVarName)
                }
            }
            DispatchQueue.main.async {
                // 再試行(Retry)時にユーザーが外したチェックを勝手に戻さない:
                // 初回ロードのみ全選択、以降は既存の選択を維持しつつ
                // 新たに読み込めたキーだけを追加選択する
                let loaded = Set(values.keys)
                if cachedValues.isEmpty {
                    selectedKeys = loaded
                } else {
                    let newlyLoaded = loaded.subtracting(cachedValues.keys)
                    selectedKeys = selectedKeys.intersection(loaded).union(newlyLoaded)
                }
                cachedValues = values
                failedKeys = failed
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
    @State private var share: KeyShareService.DecryptedShare?
    @State private var revealed: Set<String> = []          // envVarName ごとの値表示トグル
    @State private var fingerprintConfirmed = false        // 帯域外照合の必須チェック
    @State private var unsignedAck = false                 // 未署名ファイルの追加承諾
    @State private var overwriteConfirmed = false          // 既存上書きの明示承諾
    @State private var imported = false
    @State private var importCount = 0
    /// 受信キーのうち値形式が未対応（非 ASCII / 複数行 / 8KB 超）で保存できなかった件数。
    @State private var unsupportedCount = 0
    /// 値形式以外の理由（keychain ロック等）で保存できなかった件数。
    @State private var failedCount = 0
    @State private var errorMessage: String?
    // 復号時に envVarName で重複排除（先勝ち）した表示用エントリ（finding 10）と、
    // その時点で一度だけ Keychain を引いて数えた上書き件数（finding 11）。
    @State private var entries: [(envVarName: String, value: String)] = []
    @State private var overwriteNames: Set<String> = []
    // TOFU 分類（#126）と鮮度（#126）。復号時に一度だけ算出して state に持つ。
    @State private var senderTrust: FingerprintTOFUStore.SenderTrust?
    @State private var freshness: KeyShareService.Freshness?

    /// 確認済みフィンガープリントのピン留めストア（#126）。
    private let tofu = FingerprintTOFUStore()

    private var overwriteCount: Int { overwriteNames.count }

    /// インポート可能条件: 指紋照合済み ∧ (認証済み ∨ 未署名承諾) ∧ (上書き無し ∨ 上書き承諾)
    private var canImport: Bool {
        guard let share else { return false }
        let authGate = share.isAuthenticated || unsignedAck
        let overwriteGate = overwriteCount == 0 || overwriteConfirmed
        return fingerprintConfirmed && authGate && overwriteGate
    }

    var body: some View {
        VStack(spacing: 0) {
            if share == nil && !imported {
                startView
            } else if let share, !imported {
                previewView(share)
            } else {
                completeView
            }
        }
    }

    // MARK: Start

    private var startView: some View {
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
    }

    // MARK: Preview

    @ViewBuilder
    private func previewView(_ share: KeyShareService.DecryptedShare) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                senderBanner(share)

                Text(L10n.s(ja: "復号された \(entries.count) 件のキー:", en: "Decrypted \(entries.count) keys:"))
                    .font(.system(size: 12, weight: .medium))

                VStack(spacing: 0) {
                    ForEach(entries, id: \.envVarName) { entry in
                        keyRow(entry)
                        Divider()
                    }
                }
                .background(Color(.textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

                gates(share)
            }
            .padding(16)
        }

        Divider()

        HStack {
            Button("Cancel") { resetPreview() }
                .font(.system(size: 11))
            Spacer()
            Button("Import to Keychain") {
                importDecrypted()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canImport)
        }
        .padding(12)
    }

    @ViewBuilder
    private func senderBanner(_ share: KeyShareService.DecryptedShare) -> some View {
        if share.isAuthenticated, let fp = share.senderFingerprint {
            VStack(alignment: .leading, spacing: 6) {
                Label(L10n.s(ja: "送信者の署名を検証しました", en: "Sender signature verified"), systemImage: "checkmark.seal.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.configured)

                // TOFU 分類（#126）: 既知 → 緑バッジで照合負担を軽減、初見 → 中立の注記。
                tofuNote()

                Text(L10n.s(ja: "送信者フィンガープリント:", en: "Sender fingerprint:"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(fp)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                if let created = share.createdAt {
                    Text(L10n.s(ja: "作成日時: ", en: "Created: ") + created.formatted(date: .abbreviated, time: .shortened) + "（\(ageText(created))）")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }

                // 鮮度（#126）: しきい値超過は replay の疑いとして目立たせる。
                freshnessNote()

                Text(L10n.s(ja: "有効な署名は「その署名鍵の保有者が作成した」ことしか証明しません。上の指紋を信頼できる経路（対面/電話等）で送信者本人と照合してください。", en: "A valid signature only proves the file was made by whoever holds that signing key. Compare the fingerprint above with the sender over a trusted channel (in person / phone)."))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(AppColors.configured.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Label(L10n.s(ja: "送信者を認証できません", en: "Sender could NOT be authenticated"), systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.red)
                Text(L10n.s(ja: "⚠ 送信者を認証できません。このファイル (v1/未署名) はあなたの公開鍵を持つ第三者が偽造した可能性があります。攻撃者が選んだキー値を掴まされる恐れがあります。", en: "⚠ Sender could NOT be authenticated. This file (v1/unsigned) may have been forged by anyone holding your public key — the values could be attacker-chosen."))
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    /// TOFU 分類バッジ（#126）。既知＝緑「既知の送信者」、初見＝中立「初回の送信者」。
    @ViewBuilder
    private func tofuNote() -> some View {
        switch senderTrust {
        case .known(let since):
            Label(
                L10n.s(
                    ja: "既知の送信者（\(since.formatted(date: .abbreviated, time: .omitted)) に確認済み）",
                    en: "Known sender (confirmed on \(since.formatted(date: .abbreviated, time: .omitted)))"
                ),
                systemImage: "person.fill.checkmark"
            )
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(AppColors.configured)
        case .firstSeen:
            Label(
                L10n.s(ja: "初回の送信者（このフィンガープリントは初めてです）", en: "First-seen sender (this fingerprint is new)"),
                systemImage: "person.fill.questionmark"
            )
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
        case nil:
            EmptyView()
        }
    }

    /// 鮮度バッジ（#126）。stale は replay の疑いとして赤字で目立たせる。
    @ViewBuilder
    private func freshnessNote() -> some View {
        switch freshness {
        case .stale:
            HStack(spacing: 4) {
                Image(systemName: "clock.badge.exclamationmark.fill")
                Text(L10n.s(
                    ja: "⚠ このファイルは古い（30日超）です。古い署名済みファイルは、送信者が鍵をローテーション済みでも有効に見えるため、リプレイの可能性を疑ってください。",
                    en: "⚠ This file is old (>30 days). A signed old file can look valid even after the sender rotated their key — treat it as a possible replay."
                ))
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
            .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        case .fresh, nil:
            EmptyView()
        }
    }

    /// 経過時間を人間可読な相対表現にする（例: "3 days ago"）。
    private func ageText(_ created: Date) -> String {
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .full
        return fmt.localizedString(for: created, relativeTo: Date())
    }

    @ViewBuilder
    private func keyRow(_ entry: (envVarName: String, value: String)) -> some View {
        let service = ServiceType.allCases.first { $0.envVarName == entry.envVarName }
        let isRevealed = revealed.contains(entry.envVarName)
        let overwrites = overwriteNames.contains(entry.envVarName)
        HStack {
            Image(systemName: service?.systemImage ?? "key")
                .foregroundStyle(service?.category.color ?? .secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(service?.displayName ?? entry.envVarName)
                        .font(.system(size: 12, weight: .medium))
                    if overwrites {
                        Text(L10n.s(ja: "上書き", en: "Overwrite"))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                    }
                }
                Text(entry.envVarName)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Text(isRevealed ? entry.value : SecretMask.mask(entry.value))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(isRevealed ? .primary : .secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button {
                if isRevealed { revealed.remove(entry.envVarName) }
                else { revealed.insert(entry.envVarName) }
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(L10n.s(ja: "値を表示/非表示", en: "Show / hide value"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func gates(_ share: KeyShareService.DecryptedShare) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $fingerprintConfirmed) {
                // 未認証(v1)は照合すべき指紋自体が無いので、確認対象を「送信者本人への
                // 直接確認」に変える（finding 7）。
                // 既知（TOFU 確認済み）の送信者でも、安全側に倒して明示的なチェックは
                // 引き続き必須とし、文言だけ「再確認」に和らげる（#126 の設計判断）。
                Text(fingerprintGateLabel(share))
                    .font(.system(size: 11))
            }

            if !share.isAuthenticated {
                Toggle(isOn: $unsignedAck) {
                    Text(L10n.s(ja: "このファイルは送信者を認証できないことを理解し、リスクを承知でインポートします", en: "I understand this file's sender cannot be authenticated and import at my own risk"))
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
            }

            if overwriteCount > 0 {
                Toggle(isOn: $overwriteConfirmed) {
                    Text(L10n.s(ja: "既存の \(overwriteCount) 件を上書きします", en: "Overwrite \(overwriteCount) existing key(s)"))
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            }
        }
        .toggleStyle(.checkbox)
    }

    /// 指紋確認ゲートの文言。認証済み×既知は「再確認」、認証済み×初見は「照合」、
    /// 未認証は「送信者本人への直接確認」に切り替える。
    private func fingerprintGateLabel(_ share: KeyShareService.DecryptedShare) -> String {
        guard share.isAuthenticated else {
            return L10n.s(
                ja: "送信者本人に、このファイルを送ったことを信頼できる経路で直接確認しました",
                en: "I directly confirmed with the sender, over a trusted channel, that they sent this file"
            )
        }
        if senderTrust?.isKnown == true {
            return L10n.s(
                ja: "既知の送信者です。フィンガープリントが以前と同じであることを再確認しました",
                en: "This is a known sender. I re-confirmed the fingerprint matches the one I trusted before"
            )
        }
        return L10n.s(
            ja: "送信者のフィンガープリントを信頼できる経路で確認しました",
            en: "I verified the sender's fingerprint via a trusted channel"
        )
    }

    // MARK: Complete

    private var completeView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.configured)
            Text(L10n.s(ja: "\(importCount) 件のキーをインポートしました", en: "\(importCount) keys imported!"))
                .font(.system(size: 16, weight: .semibold))
            Text(L10n.s(ja: "Keychain に保存されました", en: "Saved to Keychain"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            if unsupportedCount > 0 {
                // 値形式が未対応（非 ASCII / 複数行 / 8KB 超）。C7 (#174) までの制約
                Label(L10n.s(
                    ja: "\(unsupportedCount) 件は未対応の値形式（非 ASCII / 複数行 / 8KB 超）のため保存されませんでした。",
                    en: "\(unsupportedCount) key(s) were not saved because the value format is not supported yet (non-ASCII / multi-line / over 8KB)."),
                      systemImage: "textformat.abc.dottedunderline")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            if failedCount > 0 {
                Label(L10n.s(
                    ja: "\(failedCount) 件は保存に失敗しました（Keychain のロック等）。もう一度お試しください。",
                    en: "\(failedCount) key(s) failed to save (e.g. a locked Keychain). Please try again."),
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Keychain Access.app"))
            } label: {
                Label("Open Keychain Access", systemImage: "lock.rectangle")
            }
            .buttonStyle(.bordered)

            Spacer()
        }
    }

    private func resetPreview() {
        share = nil
        entries = []
        overwriteNames = []
        revealed = []
        fingerprintConfirmed = false
        unsignedAck = false
        overwriteConfirmed = false
        senderTrust = nil
        freshness = nil
    }

    private func decryptFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "aikeychain") ?? .data]
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let decrypted = try KeyShareService.decryptAndImport(from: url)
                // envVarName で重複排除（先勝ち）。ForEach の ID 衝突と、
                // 後勝ちで意図せぬ値を保存する事故を防ぐ（finding 10）。
                var seen = Set<String>()
                let deduped = decrypted.entries.filter { seen.insert($0.envVarName).inserted }
                // 上書き対象は decrypt 時に一度だけ Keychain を引いて確定（毎描画で
                // 引かない / finding 11）。
                let owNames = Set(deduped.map(\.envVarName).filter { SecurityCLIKeychainService.shared.exists(for: $0) })
                entries = deduped
                overwriteNames = owNames
                share = decrypted
                // TOFU 分類 & 鮮度（#126）を復号時に一度だけ算出。
                if decrypted.isAuthenticated, let fp = decrypted.senderFingerprint {
                    senderTrust = tofu.classify(fp)
                } else {
                    senderTrust = nil
                }
                freshness = decrypted.createdAt.map { KeyShareService.classifyFreshness(createdAt: $0) }
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func importDecrypted() {
        guard canImport else { return }
        // 認証済みインポートを確定したら、このフィンガープリントを確認済みとして
        // ピン留めする（TOFU / #126）。次回以降は「既知の送信者」として扱える。
        if let share, share.isAuthenticated, let fp = share.senderFingerprint {
            tofu.confirm(fp)
        }
        var count = 0
        var unsupported: [String] = []
        var failed: [String] = []
        for entry in entries {
            // 外部由来の .aikeychain ファイルの envVarName は信頼できない。
            // シェル export に不正な名前はスキップする（SecurityCLIKeychainService.save 側でも
            // 弾かれるが、ここで明示的に skip して意図を明確化 / #116）。
            guard EnvVarName.isValid(entry.envVarName) else { continue }
            do {
                try SecurityCLIKeychainService.shared.save(value: entry.value, for: entry.envVarName)
                count += 1
            } catch KeychainError.invalidData {
                // 値形式が未対応（非 ASCII / 複数行 / 8KB 超）。share フォーマット自体は
                // UTF-8 を運べるため、受信側の制約として理由付きで surface する
                // （#179 二段レビュー N1/D-Q1。C7 #174 のエンコーディング規約で解消予定）。
                unsupported.append(entry.envVarName)
            } catch {
                // その他の失敗（keychain ロック等）は理由別に別集計。
                // 誤案内で本当の失敗を隠さないため（codex 指摘）。
                failed.append(entry.envVarName)
            }
        }
        importCount = count
        unsupportedCount = unsupported.count
        failedCount = failed.count
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
