import SwiftUI

struct KeyRowView: View {
    let key: APIKey

    var body: some View {
        HStack(spacing: 12) {
            if let service = key.service {
                ServiceIcon(service: service)
            } else {
                Image(systemName: key.systemImage)
                    .font(.system(size: 16))
                    .foregroundStyle(key.categoryColor)
                    .frame(width: 32, height: 32)
                    .background(key.categoryColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(key.displayName)
                    .font(.system(size: 14, weight: .medium))
                Text(key.envVarName)
                    .font(AppFonts.code)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            StatusBadge(isConfigured: key.isConfigured)
        }
        .padding(.vertical, 4)
    }
}
