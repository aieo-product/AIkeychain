import SwiftUI

struct MainView: View {
    @State private var viewModel = KeyListViewModel()
    @State private var showingExport = false
    @State private var showingSetup = !SetupManager.isConfigured()

    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel)
        } detail: {
            KeyListView(viewModel: viewModel)
        }
        .searchable(text: $viewModel.searchText, prompt: "Search keys...")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingExport = true
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: $viewModel.showingEditor) {
            viewModel.loadKeys()
        } content: {
            KeyEditorView(
                editingKey: viewModel.editingKey,
                onSave: { viewModel.loadKeys() }
            )
        }
        .sheet(isPresented: $showingExport) {
            ExportView(keys: viewModel.keys)
        }
        .sheet(isPresented: $showingSetup) {
            SetupView()
        }
        .frame(minWidth: 700, minHeight: 450)
    }
}
