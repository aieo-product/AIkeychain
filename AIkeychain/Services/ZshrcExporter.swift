import Foundation

enum ExportFormat: String, CaseIterable, Identifiable {
    case zshrc = ".zshrc (Keychain reference)"
    case secretRef = ".zshrc (Secret Reference)"
    case env = ".env (plaintext)"

    var id: String { rawValue }
}

struct ZshrcExporter {
    static func export(keys: [APIKey], format: ExportFormat) -> String {
        let configured = keys.filter(\.isConfigured)

        switch format {
        case .zshrc:
            return generateZshrc(keys: configured)
        case .secretRef:
            return generateSecretRef(keys: configured)
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
                lines.append("# [AI KeyChain] \(key.displayName)")
                // GUI の保存形式 (service=com.aieo.aikeychain, account=KEY_NAME) を先に
                // 引き、無ければ manual スキーム (service=KEY_NAME) に fallback する。
                // CLI (`akc`) の 2 段ルックアップと同じ順序 (#91, #160)。
                // -a "$USER" は acct のずれ/重複で古い値を掴む恐れがあるため使わない。
                lines.append("export \(key.envVarName)=$(/usr/bin/security find-generic-password -s \"com.aieo.aikeychain\" -a \"\(key.envVarName)\" -w 2>/dev/null || /usr/bin/security find-generic-password -s \"\(key.envVarName)\" -w)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private static func generateSecretRef(keys: [APIKey]) -> String {
        var lines: [String] = [
            "# AI KeyChain - Secret Reference exports",
            "# Keys are resolved at runtime via 'akc run'",
            "# Usage: akc run -- <command>",
            "#",
            "# Generated: \(formattedDate())",
            "",
        ]

        let grouped = Dictionary(grouping: keys) { $0.builtinCategory }

        for category in KeyCategory.allCases {
            guard let categoryKeys = grouped[category], !categoryKeys.isEmpty else { continue }

            lines.append("# --- \(category.rawValue) ---")
            for key in categoryKeys {
                lines.append("# [AI KeyChain] \(key.displayName)")
                lines.append("export \(key.envVarName)=\"keychain://\(key.envVarName)\"")
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
            lines.append("# \(key.displayName)")
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
