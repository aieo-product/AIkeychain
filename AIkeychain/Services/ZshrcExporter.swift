import Foundation

enum ExportFormat: String, CaseIterable, Identifiable {
    case zshrc = ".zshrc (Keychain reference)"
    case env = ".env (plaintext)"

    var id: String { rawValue }
}

struct ZshrcExporter {
    static func export(keys: [APIKey], format: ExportFormat) -> String {
        let configured = keys.filter(\.isConfigured)

        switch format {
        case .zshrc:
            return generateZshrc(keys: configured)
        case .env:
            return generateEnv(keys: configured)
        }
    }

    private static func generateZshrc(keys: [APIKey]) -> String {
        var lines: [String] = [
            "# AI KeyChain - Generated exports",
            "# Tokens are stored in macOS Keychain (not plaintext)",
            "#",
            "# Generated: \(formattedDate())",
            "",
        ]

        let grouped = Dictionary(grouping: keys) { $0.builtinCategory }

        for category in KeyCategory.allCases {
            guard let categoryKeys = grouped[category], !categoryKeys.isEmpty else { continue }

            lines.append("# --- \(category.rawValue) ---")
            for key in categoryKeys {
                lines.append("export \(key.envVarName)=$(security find-generic-password -s \"\(key.envVarName)\" -a \"$USER\" -w)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private static func generateEnv(keys: [APIKey]) -> String {
        var lines: [String] = [
            "# AI KeyChain - Generated .env",
            "# WARNING: This file contains references, not actual values.",
            "# Replace <VALUE> with actual token values.",
            "#",
            "# Generated: \(formattedDate())",
            "",
        ]

        for key in keys {
            lines.append("\(key.envVarName)=<VALUE>")
        }

        return lines.joined(separator: "\n")
    }

    private static func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: Date())
    }
}
