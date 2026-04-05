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
                    Text("\(viewModel.filteredKeys.count) keys")
                        .font(AppFonts.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    showingImport = true
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }

                Button {
                    viewModel.addNewKey()
                } label: {
                    Label("Add Key", systemImage: "plus")
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
                    Text("No Keys Found")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Add Key or Import to get started.")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            } else {
                List(viewModel.filteredKeys, selection: $viewModel.selectedKey) { key in
                    KeyRowView(key: key)
                        .tag(key)
                        .contextMenu {
                            Button("Edit") { viewModel.editKey(key) }
                            Button("Copy Env Name") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(key.envVarName, forType: .string)
                            }
                            if key.isConfigured {
                                Button("Copy Value") {
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
                                Button("Open Setup Page") {
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
        guard let sel = viewModel.selectedCategory else { return "All Keys" }
        switch sel {
        case .all: return "All Keys"
        case .builtin(let cat): return cat.rawValue
        case .custom(let id):
            return CustomKeyStore.shared.category(for: id)?.name ?? "Custom"
        case .activity:
            return "Activity"
        }
    }
}
