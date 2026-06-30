import SwiftUI

struct SidebarView: View {
    @Bindable var viewModel: KeyListViewModel
    @State private var showingCategoryEditor = false

    private var customStore: CustomKeyStore { .shared }

    private var appState: AppState { .shared }
    private var logStore: ProxyLogStore { appState.proxyLogStore }

    var body: some View {
        List(selection: $viewModel.selectedCategory) {
            Section {
                NavigationLink(value: CategorySelection.all) {
                    Label {
                        HStack {
                            Text(L10n.s(ja: "すべてのキー", en: "All Keys"))
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

                NavigationLink(value: CategorySelection.activity) {
                    Label {
                        HStack {
                            Text(L10n.s(ja: "アクティビティ", en: "Activity"))
                            Spacer()
                            if appState.isProxyMode && logStore.todayCount > 0 {
                                Text("\(logStore.todayCount)")
                                    .font(AppFonts.badge)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: "chart.bar.fill")
                            .foregroundStyle(.blue)
                    }
                }
            }

            Section(L10n.s(ja: "カテゴリ", en: "Categories")) {
                ForEach(KeyCategory.allCases) { category in
                    NavigationLink(value: CategorySelection.builtin(category)) {
                        Label {
                            HStack {
                                Text(category.displayName)
                                Spacer()
                                Text("\(viewModel.builtinCategoryConfiguredCount(for: category))/\(viewModel.builtinCategoryCount(for: category))")
                                    .font(AppFonts.badge)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            CategoryIcon(category: category, size: 22)
                        }
                    }
                }
            }

            if !customStore.categories.isEmpty {
                Section(L10n.s(ja: "カスタム", en: "Custom")) {
                    ForEach(customStore.categories) { category in
                        NavigationLink(value: CategorySelection.custom(category.id)) {
                            Label {
                                HStack {
                                    Text(category.name)
                                    Spacer()
                                    Text("\(viewModel.customCategoryConfiguredCount(for: category.id))/\(viewModel.customCategoryCount(for: category.id))")
                                        .font(AppFonts.badge)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: category.systemImage)
                                    .foregroundStyle(category.color)
                                    .frame(width: 22, height: 22)
                            }
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

                Button {
                    showingCategoryEditor = true
                } label: {
                    Label(L10n.s(ja: "カテゴリを管理", en: "Manage Categories"), systemImage: "folder.badge.gearshape")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Label(L10n.s(ja: "\(viewModel.configuredCount) 設定済み", en: "\(viewModel.configuredCount) configured"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(AppColors.configured)
                    Label(L10n.s(ja: "\(viewModel.pendingCount) 未設定", en: "\(viewModel.pendingCount) pending"), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppColors.pending)
                }
                .font(AppFonts.badge)
                .padding(.bottom, 8)
            }
        }
        .sheet(isPresented: $showingCategoryEditor) {
            CategoryManagerView()
        }
    }
}
