import SwiftUI

/// カスタムカテゴリの管理画面
struct CategoryManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var customStore = CustomKeyStore.shared
    @State private var editingCategory: CustomCategory?
    @State private var showingEditor = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 24))
                    .foregroundStyle(AppColors.accentGradient)
                VStack(alignment: .leading) {
                    Text("Manage Categories")
                        .font(AppFonts.sectionTitle)
                    Text(L10n.s(ja: "カテゴリの追加・編集・削除", en: "Add, edit, and delete categories"))
                        .font(AppFonts.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider()

            List {
                // Built-in categories (read only)
                Section("Built-in") {
                    ForEach(KeyCategory.allCases) { category in
                        HStack(spacing: 10) {
                            Image(systemName: category.systemImage)
                                .foregroundStyle(category.color)
                                .frame(width: 24)
                            Text(category.rawValue)
                                .font(.system(size: 13))
                            Spacer()
                            Text("Built-in")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                // Custom categories
                Section("Custom") {
                    ForEach(customStore.categories) { category in
                        HStack(spacing: 10) {
                            Image(systemName: category.systemImage)
                                .foregroundStyle(category.color)
                                .frame(width: 24)
                            Text(category.name)
                                .font(.system(size: 13))
                            Spacer()
                            Button {
                                editingCategory = category
                                showingEditor = true
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)

                            Button {
                                customStore.deleteCategory(category.id)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.red.opacity(0.7))
                        }
                    }

                    if customStore.categories.isEmpty {
                        Text(L10n.s(ja: "カスタムカテゴリはまだありません", en: "No custom categories yet"))
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .listStyle(.inset)

            Divider()

            HStack {
                Button("Add Category") {
                    editingCategory = nil
                    showingEditor = true
                }
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding(16)
        }
        .frame(width: 460, height: 480)
        .sheet(isPresented: $showingEditor) {
            CategoryEditorView(category: editingCategory) { saved in
                if let existing = editingCategory {
                    var updated = existing
                    updated.name = saved.name
                    updated.systemImage = saved.systemImage
                    updated.colorHex = saved.colorHex
                    customStore.updateCategory(updated)
                } else {
                    customStore.addCategory(saved)
                }
            }
        }
    }
}

/// カテゴリ編集ダイアログ
struct CategoryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let category: CustomCategory?
    let onSave: (CustomCategory) -> Void

    @State private var name: String = ""
    @State private var selectedIcon: String = "folder"
    @State private var selectedColorHex: UInt = 0x6B7280

    private let iconOptions = [
        "folder", "tray.full", "cpu", "server.rack", "globe",
        "doc.text", "hammer", "paintbrush", "chart.bar", "lock.shield",
        "creditcard", "cart", "envelope", "antenna.radiowaves.left.and.right",
        "gamecontroller", "camera", "music.note", "photo", "video",
        "wand.and.stars", "testtube.2", "leaf", "bolt", "flame",
    ]

    private let colorOptions: [(String, UInt)] = [
        ("Red", 0xDC2626), ("Orange", 0xEA580C), ("Amber", 0xD97706),
        ("Green", 0x059669), ("Teal", 0x0D9488), ("Blue", 0x2563EB),
        ("Indigo", 0x4F46E5), ("Purple", 0x7C3AED), ("Pink", 0xDB2777),
        ("Gray", 0x6B7280),
    ]

    var body: some View {
        VStack(spacing: 16) {
            Text(category == nil ? "New Category" : "Edit Category")
                .font(.system(size: 15, weight: .semibold))

            // Name
            TextField("Category Name", text: $name)
                .textFieldStyle(.roundedBorder)

            // Icon picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Icon")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(32)), count: 8), spacing: 6) {
                    ForEach(iconOptions, id: \.self) { icon in
                        Button {
                            selectedIcon = icon
                        } label: {
                            Image(systemName: icon)
                                .font(.system(size: 14))
                                .frame(width: 28, height: 28)
                                .background(
                                    selectedIcon == icon
                                        ? Color(hex: selectedColorHex).opacity(0.2)
                                        : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 6)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(selectedIcon == icon ? Color(hex: selectedColorHex) : Color.clear, lineWidth: 1.5)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Color picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Color")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(colorOptions, id: \.1) { name, hex in
                        Button {
                            selectedColorHex = hex
                        } label: {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Circle()
                                        .stroke(.white, lineWidth: selectedColorHex == hex ? 2 : 0)
                                        .shadow(radius: selectedColorHex == hex ? 2 : 0)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(name)
                    }
                }
            }

            // Preview
            HStack(spacing: 8) {
                Image(systemName: selectedIcon)
                    .foregroundStyle(Color(hex: selectedColorHex))
                    .frame(width: 22, height: 22)
                Text(name.isEmpty ? "Preview" : name)
                    .font(.system(size: 13))
                    .foregroundStyle(name.isEmpty ? .tertiary : .primary)
            }
            .padding(8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") {
                    onSave(CustomCategory(
                        id: category?.id ?? UUID(),
                        name: name,
                        systemImage: selectedIcon,
                        colorHex: selectedColorHex
                    ))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360, height: 420)
        .onAppear {
            if let category {
                name = category.name
                selectedIcon = category.systemImage
                selectedColorHex = category.colorHex
            }
        }
    }
}
