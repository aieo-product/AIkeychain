import SwiftUI

struct KeyListView: View {
    @Bindable var viewModel: KeyListViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.selectedCategory?.rawValue ?? "All Keys")
                        .font(AppFonts.sectionTitle)
                    Text("\(viewModel.filteredKeys.count) keys")
                        .font(AppFonts.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    viewModel.addNewKey()
                } label: {
                    Label("Add Key", systemImage: "plus")
                }
            }
            .padding()

            Divider()

            // Key list
            if viewModel.filteredKeys.isEmpty {
                ContentUnavailableView {
                    Label("No Keys Found", systemImage: "key.slash")
                } description: {
                    Text("No keys match your search.")
                }
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
                            if let url = key.service.setupURL {
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
}
