import SwiftUI

/// キー/カテゴリの表示アイコンを選ぶ共通グリッド。
/// 選択中アイコンを `selection` にバインドし、`tint` で強調色を指定する。
struct IconPickerGrid: View {
    @Binding var selection: String
    var tint: Color = AppColors.aiPurple
    var columns: Int = 8

    /// 選択肢。カテゴリ用の汎用アイコン + サービスを想起させるアイコンを含む。
    static let options: [String] = [
        // カテゴリ汎用
        "folder", "tray.full", "cpu", "server.rack", "globe",
        "doc.text", "hammer", "paintbrush", "chart.bar", "lock.shield",
        "creditcard", "cart", "envelope", "antenna.radiowaves.left.and.right",
        "gamecontroller", "camera", "music.note", "photo", "video",
        "wand.and.stars", "testtube.2", "leaf", "bolt", "flame",
        // サービス想起
        "key", "brain", "sparkles", "bolt.fill", "waveform",
        "chevron.left.forwardslash.chevron.right", "cloud.fill", "network",
        "message.fill", "number", "bubble.left.and.bubble.right.fill",
        "brain.head.profile", "wrench.and.screwdriver.fill", "face.smiling",
        "star.fill", "tag.fill", "shippingbox.fill", "terminal.fill",
    ]

    /// 現在の選択が選択肢に無い場合（既存キーのサービスアイコン等）でも
    /// 選択状態が見えるよう、先頭に補う。
    private var displayedOptions: [String] {
        if !selection.isEmpty && !Self.options.contains(selection) {
            return [selection] + Self.options
        }
        return Self.options
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(32)), count: columns), spacing: 6) {
            ForEach(displayedOptions, id: \.self) { icon in
                Button {
                    selection = icon
                } label: {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .frame(width: 28, height: 28)
                        .background(
                            selection == icon ? tint.opacity(0.2) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(selection == icon ? tint : Color.clear, lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)
                .help(icon)
            }
        }
    }
}
