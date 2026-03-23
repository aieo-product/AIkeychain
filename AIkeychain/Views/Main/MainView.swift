import SwiftUI

struct MainView: View {
    @State private var viewModel = KeyListViewModel()
    @State private var showingExport = false
    @State private var showingHelp = false
    @State private var showingOnboarding = !OnboardingViewModel.hasCompleted

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
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingHelp = true
                } label: {
                    Label("Help", systemImage: "questionmark.circle")
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
        .sheet(isPresented: $showingHelp) {
            HelpView()
        }
        .sheet(isPresented: $showingOnboarding) {
            OnboardingView()
        }
        .frame(minWidth: 700, minHeight: 450)
    }
}
