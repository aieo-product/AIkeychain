import SwiftUI

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

enum AppColors {
    // Category
    static let aiPurple = Color(hex: 0x7C3AED)
    static let gitOrange = Color(hex: 0xEA580C)
    static let cloudBlue = Color(hex: 0x0284C7)
    static let commGreen = Color(hex: 0x059669)
    static let toolsGray = Color(hex: 0x6B7280)

    // Status
    static let configured = Color(hex: 0x10B981)
    static let pending = Color(hex: 0xF59E0B)

    // Accent gradient
    static let accentGradient = LinearGradient(
        colors: [aiPurple, cloudBlue, commGreen],
        startPoint: .leading,
        endPoint: .trailing
    )

    // Background
    static let cardBackground = Color(.windowBackgroundColor)
    static let sidebarBackground = Color(.controlBackgroundColor)
}
