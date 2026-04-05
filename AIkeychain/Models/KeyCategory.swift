import SwiftUI

enum KeyCategory: String, CaseIterable, Identifiable {
    case ai = "AI API"
    case webAuth = "AI Web"
    case codeAndGit = "Code & Git"
    case cloud = "Cloud & Infra"
    case communication = "Communication"
    case devTools = "Developer Tools"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .ai: Color(hex: 0x7C3AED)
        case .webAuth: Color(hex: 0xDB2777)
        case .codeAndGit: Color(hex: 0xEA580C)
        case .cloud: Color(hex: 0x0284C7)
        case .communication: Color(hex: 0x059669)
        case .devTools: Color(hex: 0x6B7280)
        }
    }

    var systemImage: String {
        switch self {
        case .ai: "brain.head.profile"
        case .webAuth: "globe"
        case .codeAndGit: "chevron.left.forwardslash.chevron.right"
        case .cloud: "cloud.fill"
        case .communication: "bubble.left.and.bubble.right.fill"
        case .devTools: "wrench.and.screwdriver.fill"
        }
    }

    /// ビルトインカテゴリの安定 UUID（CustomKey.categoryId として使用）
    var stableId: UUID {
        switch self {
        case .ai:            UUID(uuidString: "B0000000-0000-0000-0000-000000000001")!
        case .webAuth:       UUID(uuidString: "B0000000-0000-0000-0000-000000000002")!
        case .codeAndGit:    UUID(uuidString: "B0000000-0000-0000-0000-000000000003")!
        case .cloud:         UUID(uuidString: "B0000000-0000-0000-0000-000000000004")!
        case .communication: UUID(uuidString: "B0000000-0000-0000-0000-000000000005")!
        case .devTools:      UUID(uuidString: "B0000000-0000-0000-0000-000000000006")!
        }
    }

    /// stableId からビルトインカテゴリを逆引き
    static func from(stableId: UUID) -> KeyCategory? {
        allCases.first { $0.stableId == stableId }
    }
}
