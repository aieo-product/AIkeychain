import SwiftUI

struct KeyEditorView: View {
    @State private var viewModel: KeyEditorViewModel
    @Environment(\.dismiss) private var dismiss
    let onSave: () -> Void

    init(editingKey: APIKey? = nil, onSave: @escaping () -> Void = {}) {
        _viewModel = State(initialValue: KeyEditorViewModel(editingKey: editingKey))
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(viewModel.title)
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

            // Form
            Form {
                // Category (required)
                Picker(L10n.s(ja: "カテゴリ", en: "Category"), selection: $viewModel.selectedCategorySelection) {
                    Text(L10n.s(ja: "カテゴリを選択...", en: "Select a category..."))
                        .foregroundStyle(.secondary)
                        .tag(CategorySelection?.none)
                    ForEach(KeyCategory.allCases) { cat in
                        Label(cat.displayName, systemImage: cat.systemImage)
                            .tag(CategorySelection?.some(.builtin(cat)))
                    }
                    if !CustomKeyStore.shared.categories.isEmpty {
                        Divider()
                        ForEach(CustomKeyStore.shared.categories) { cat in
                            Label(cat.name, systemImage: cat.systemImage)
                                .tag(CategorySelection?.some(.custom(cat.id)))
                        }
                    }
                }
                .onChange(of: viewModel.selectedCategorySelection) {
                    viewModel.categoryDidChange()
                }

                // Env var name (required)
                TextField(L10n.s(ja: "環境変数名", en: "Environment Variable"), text: $viewModel.envVarName)
                    .font(AppFonts.code)

                // Icon picker — pick the symbol shown for this key in its category.
                Section {
                    IconPickerGrid(
                        selection: Binding(
                            get: { viewModel.selectedIcon },
                            set: { viewModel.pickIcon($0) }
                        ),
                        tint: categoryColor(viewModel.selectedCategorySelection)
                    )
                } header: {
                    Text(L10n.s(ja: "アイコン", en: "Icon"))
                } footer: {
                    Text(L10n.s(ja: "一覧でこのキーに表示するアイコンを選びます。",
                                en: "Choose the icon shown for this key in the list."))
                        .font(AppFonts.caption)
                        .foregroundStyle(.secondary)
                }

                // Token value
                Section {
                    HStack {
                        if viewModel.showToken {
                            TextField(L10n.s(ja: "トークンの値", en: "Token Value"), text: $viewModel.tokenValue)
                                .font(AppFonts.code)
                        } else {
                            SecureField(L10n.s(ja: "トークンの値", en: "Token Value"), text: $viewModel.tokenValue)
                                .font(AppFonts.code)
                        }
                        Button {
                            viewModel.showToken.toggle()
                        } label: {
                            Image(systemName: viewModel.showToken ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                    }

                    if let warning = viewModel.prefixWarning {
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(AppFonts.caption)
                            .foregroundStyle(AppColors.pending)
                    }
                }

                // Setup URL (existing preset keys only)
                if let url = viewModel.selectedService?.setupURL {
                    Section {
                        Link(destination: url) {
                            Label(L10n.s(ja: "トークンを取得", en: "Get Token"), systemImage: "arrow.up.right.square")
                        }
                    }
                }
            }
            .formStyle(.grouped)

            // Error message
            if let error = viewModel.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(AppFonts.caption)
                    .padding(.horizontal)
            }

            Divider()

            // Actions
            HStack {
                if viewModel.isEditing {
                    Button(L10n.s(ja: "削除", en: "Delete"), role: .destructive) {
                        viewModel.showDeleteConfirm = true
                    }
                }

                Spacer()

                Button(L10n.s(ja: "キャンセル", en: "Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button(viewModel.showSaveSuccess
                       ? L10n.s(ja: "保存しました", en: "Saved!")
                       : L10n.s(ja: "Keychain に保存", en: "Save to Keychain")) {
                    do {
                        try viewModel.save()
                        onSave()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            dismiss()
                        }
                    } catch {
                        // Error is displayed in viewModel.errorMessage
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.canSave)
            }
            .padding()
        }
        .frame(width: 520, height: 480)
        .alert(L10n.s(ja: "キーを削除しますか？", en: "Delete Key?"), isPresented: $viewModel.showDeleteConfirm) {
            Button(L10n.s(ja: "キャンセル", en: "Cancel"), role: .cancel) {}
            Button(L10n.s(ja: "削除", en: "Delete"), role: .destructive) {
                do {
                    try viewModel.deleteKey()
                    onSave()
                    dismiss()
                } catch {
                    viewModel.errorMessage = error.localizedDescription
                }
            }
        } message: {
            Text(L10n.s(ja: "このキーを Keychain から削除します。この操作は取り消せません。",
                        en: "This will remove the key from Keychain. This action cannot be undone."))
        }
    }

    /// 選択中カテゴリの強調色（アイコンピッカーの tint）。
    private func categoryColor(_ sel: CategorySelection?) -> Color {
        switch sel {
        case .builtin(let cat): return cat.color
        case .custom(let id): return CustomKeyStore.shared.category(for: id)?.color ?? AppColors.aiPurple
        default: return AppColors.aiPurple
        }
    }
}
