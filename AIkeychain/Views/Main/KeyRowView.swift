import SwiftUI

struct KeyRowView: View {
    let key: APIKey

    var body: some View {
        HStack(spacing: 12) {
            ServiceIcon(service: key.service)

            VStack(alignment: .leading, spacing: 2) {
                Text(key.service.displayName)
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
