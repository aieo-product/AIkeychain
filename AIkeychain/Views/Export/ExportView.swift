import SwiftUI

struct ExportView: View {
    let keys: [APIKey]
    @State private var selectedFormat: ExportFormat = .zshrc
    @State private var exportText: String = ""
    @State private var copied = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(L10n.t("export_title"))
                    .font(AppFonts.sectionTitle)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Format picker
            Picker(L10n.t("export_format"), selection: $selectedFormat) {
                ForEach(ExportFormat.allCases) { format in
                    Text(format.rawValue).tag(format)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            .onChange(of: selectedFormat) {
                updateExport()
            }

            // Preview
            ScrollView {
                Text(exportText)
                    .font(AppFonts.code)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .textSelection(.enabled)
            }
            .background(Color(.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal)

            // Info
            HStack {
                Image(systemName: "info.circle")
                Text(L10n.t("export_count").replacingOccurrences(of: "%d", with: "\(keys.filter(\.isConfigured).count)"))
                    .font(AppFonts.caption)
            }
            .foregroundStyle(.secondary)
            .padding(.top, 8)

            Divider()
                .padding(.top, 8)

            // Actions
            HStack {
                Spacer()
                Button(L10n.t("cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(exportText, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copied = false
                    }
                } label: {
                    Label(copied ? L10n.t("export_copied") : L10n.t("export_copy"), systemImage: copied ? "checkmark" : "doc.on.doc")
                }

                Button(L10n.t("export_save")) {
                    saveToFile()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 560, height: 480)
        .onAppear { updateExport() }
    }

    private func updateExport() {
        exportText = ZshrcExporter.export(keys: keys, format: selectedFormat)
    }

    private func saveToFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        switch selectedFormat {
        case .zshrc: panel.nameFieldStringValue = "keychain_exports.sh"
        case .secretRef: panel.nameFieldStringValue = "secret_ref_exports.sh"
        case .env: panel.nameFieldStringValue = ".env"
        }

        if panel.runModal() == .OK, let url = panel.url {
            try? exportText.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
