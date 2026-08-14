import Foundation

enum ExportFormat: String, CaseIterable, Identifiable {
    case zshrc = ".zshrc (Keychain reference)"
    case secretRef = ".zshrc (Secret Reference)"
    case env = ".env (plaintext)"

    var id: String { rawValue }
}

struct ZshrcExporter {
    /// - Parameter managedExists: managed namespace (com.aieo.aikeychain.managed) に
    ///   キーが存在するかの判定。既定は実 Keychain への属性照会（値は読まないため
    ///   承認 UI は出ない）。テストからは差し替える。
    static func export(keys: [APIKey], format: ExportFormat,
                       managedExists: (String) -> Bool = {
                           SecurityCLIKeychainService.shared.exists(for: $0)
                       }) -> String {
        let configured = keys.filter(\.isConfigured)

        switch format {
        case .zshrc:
            return generateZshrc(keys: configured, managedExists: managedExists)
        case .secretRef:
            return generateSecretRef(keys: configured)
        case .env:
            return generateEnv(keys: configured)
        }
    }

    private static func generateZshrc(keys: [APIKey], managedExists: (String) -> Bool) -> String {
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
                // キーの実保存スキームに厳密一致する lookup だけを出す (#91, #160)。
                // シェル側の `||` フォールバックは使わない — 承認拒否や一時エラーでも
                // 別スキームの古い/無関係な値へ静かに落ちてしまうため。
                // -a "$USER" は acct のずれ/重複で古い値を掴む恐れがあるため使わない。
                // .app キーは export 時点の実在場所で判定する: GUI の新規保存は
                // managed namespace (#167/#169) へ行くため、旧 service 固定のままだと
                // 保存直後のキーが新しいシェルで空になる（#179 二段レビュー B1）。
                switch key.storage {
                case .app where managedExists(key.envVarName):
                    lines.append("export \(key.envVarName)=$(/usr/bin/security find-generic-password -s \"\(SecurityCLIKeychainService.managedService)\" -a \"\(key.envVarName)\" -w)")
                case .app:
                    lines.append("export \(key.envVarName)=$(/usr/bin/security find-generic-password -s \"com.aieo.aikeychain\" -a \"\(key.envVarName)\" -w)")
                case .manual:
                    lines.append("export \(key.envVarName)=$(/usr/bin/security find-generic-password -s \"\(key.envVarName)\" -w)")
                }
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
