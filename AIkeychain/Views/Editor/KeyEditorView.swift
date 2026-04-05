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
                // Service picker
                if !viewModel.isEditing {
                    Picker("Service", selection: $viewModel.selectedService) {
                        Text("Select a service...")
                            .foregroundStyle(.secondary)
                            .tag(ServiceType?.none)
                        ForEach(ServiceType.allCases) { service in
                            Label(service.displayName, systemImage: service.systemImage)
                                .tag(ServiceType?.some(service))
                        }
                    }
                    .onChange(of: viewModel.selectedService) {
                        viewModel.onServiceChange()
                    }
                } else if let service = viewModel.selectedService {
                    LabeledContent("Service") {
                        HStack(spacing: 8) {
                            Image(systemName: service.systemImage)
                                .foregroundStyle(service.category.color)
                            Text(service.displayName)
                        }
                    }
                }

                // Category
                Picker("Category", selection: $viewModel.selectedCategorySelection) {
                    Text("Select a category...")
                        .foregroundStyle(.secondary)
                        .tag(CategorySelection?.none)
                    ForEach(KeyCategory.allCases) { cat in
                        Label(cat.rawValue, systemImage: cat.systemImage)
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

                // Env var name
                TextField("Environment Variable", text: $viewModel.envVarName)
                    .font(AppFonts.code)

                // Token value
                Section {
                    HStack {
                        if viewModel.showToken {
                            TextField("Token Value", text: $viewModel.tokenValue)
                                .font(AppFonts.code)
                        } else {
                            SecureField("Token Value", text: $viewModel.tokenValue)
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

                // Setup URL
                if let url = viewModel.selectedService?.setupURL {
                    Section {
                        Link(destination: url) {
                            Label("Get Token", systemImage: "arrow.up.right.square")
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
                    Button("Delete", role: .destructive) {
                        viewModel.showDeleteConfirm = true
                    }
                }

                Spacer()

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button(viewModel.showSaveSuccess ? "Saved!" : "Save to Keychain") {
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
        .frame(width: 520, height: 460)
        .alert("Delete Key?", isPresented: $viewModel.showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                do {
                    try viewModel.deleteKey()
                    onSave()
                    dismiss()
                } catch {
                    viewModel.errorMessage = error.localizedDescription
                }
            }
        } message: {
            Text("This will remove the key from Keychain. This action cannot be undone.")
        }
    }
}
