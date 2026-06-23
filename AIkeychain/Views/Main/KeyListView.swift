import SwiftUI

struct KeyListView: View {
    @Bindable var viewModel: KeyListViewModel
    @State private var showingImport = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedCategoryName)
                        .font(AppFonts.sectionTitle)
                    Text(L10n.s(ja: "\(viewModel.filteredKeys.count) 件のキー", en: "\(viewModel.filteredKeys.count) keys"))
                        .font(AppFonts.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    showingImport = true
                } label: {
                    Label(L10n.s(ja: "インポート", en: "Import"), systemImage: "square.and.arrow.down")
                }

                Button {
                    viewModel.addNewKey()
                } label: {
                    Label(L10n.s(ja: "キーを追加", en: "Add Key"), systemImage: "plus")
                }
            }
            .padding()
            .sheet(isPresented: $showingImport) {
                EnvImportView {
                    viewModel.loadKeys()
                }
            }

            Divider()

            // Key list
            if viewModel.filteredKeys.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "key.slash")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text(L10n.s(ja: "キーがありません", en: "No Keys Found"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(L10n.s(ja: "「キーを追加」またはインポートで始めましょう。", en: "Add Key or Import to get started."))
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            } else {
                List(viewModel.filteredKeys, selection: $viewModel.selectedKey) { key in
                    KeyRowView(key: key)
                        .tag(key)
                        .contextMenu {
                            Button(L10n.s(ja: "編集", en: "Edit")) { viewModel.editKey(key) }
                            Button(L10n.s(ja: "変数名をコピー", en: "Copy Env Name")) {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(key.envVarName, forType: .string)
                            }
                            if key.isConfigured {
                                Button(L10n.s(ja: "値をコピー", en: "Copy Value")) {
                                    if let value = viewModel.retrieveValue(for: key) {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(value, forType: .string)
                                        // Auto-clear after 30 seconds
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                                            NSPasteboard.general.clearContents()
                                        }
                                    }
                                }
                            }
                            Divider()
                            if let url = key.setupURL {
                                Button(L10n.s(ja: "取得ページを開く", en: "Open Setup Page")) {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                        .onTapGesture(count: 2) {
                            viewModel.editKey(key)
                        }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
    }

    private var selectedCategoryName: String {
        guard let sel = viewModel.selectedCategory else { return L10n.s(ja: "すべてのキー", en: "All Keys") }
        switch sel {
        case .all: return L10n.s(ja: "すべてのキー", en: "All Keys")
        case .builtin(let cat): return cat.displayName
        case .custom(let id):
            return CustomKeyStore.shared.category(for: id)?.name ?? L10n.s(ja: "カスタム", en: "Custom")
        case .activity:
            return L10n.s(ja: "アクティビティ", en: "Activity")
        }
    }
}
