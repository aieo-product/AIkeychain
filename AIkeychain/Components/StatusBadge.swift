import SwiftUI

struct StatusBadge: View {
    let isConfigured: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isConfigured ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 10))
            Text(isConfigured ? L10n.s(ja: "設定済み", en: "Configured") : L10n.s(ja: "未設定", en: "Pending"))
                .font(AppFonts.badge)
        }
        .foregroundStyle(isConfigured ? AppColors.configured : AppColors.pending)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            (isConfigured ? AppColors.configured : AppColors.pending).opacity(0.12),
            in: Capsule()
        )
    }
}
