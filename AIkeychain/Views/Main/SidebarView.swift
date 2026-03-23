import SwiftUI

struct SidebarView: View {
    @Bindable var viewModel: KeyListViewModel

    var body: some View {
        List(selection: $viewModel.selectedCategory) {
            Section {
                NavigationLink(value: nil as KeyCategory?) {
                    Label {
                        HStack {
                            Text("All Keys")
                            Spacer()
                            Text("\(viewModel.configuredCount)/\(viewModel.keys.count)")
                                .font(AppFonts.badge)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "key.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Categories") {
                ForEach(KeyCategory.allCases) { category in
                    NavigationLink(value: category as KeyCategory?) {
                        Label {
                            HStack {
                                Text(category.rawValue)
                                Spacer()
                                Text("\(viewModel.categoryConfiguredCount(for: category))/\(viewModel.categoryCount(for: category))")
                                    .font(AppFonts.badge)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            CategoryIcon(category: category, size: 22)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                Divider()
                HStack(spacing: 12) {
                    Label("\(viewModel.configuredCount) configured", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(AppColors.configured)
                    Label("\(viewModel.pendingCount) pending", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppColors.pending)
                }
                .font(AppFonts.badge)
                .padding(.bottom, 8)
            }
        }
    }
}
