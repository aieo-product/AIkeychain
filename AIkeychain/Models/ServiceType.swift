import Foundation

enum ServiceType: String, CaseIterable, Identifiable {
    // AI API
    case anthropic
    case openAI
    case xAI
    case higgsfield

    // AI Web (認証情報)
    case anthropicWeb
    case openAIWeb
    case googleAIStudio
    case huggingFace
    case replicateWeb

    // Code & Git
    case github
    case gitlab

    // Cloud
    case cloudflareAPI
    case cloudflareAccount
    case tailscale

    // Communication
    case discord
    case slack

    // Dev Tools
    case qiita

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anthropic: "Anthropic (Claude)"
        case .openAI: "OpenAI"
        case .xAI: "xAI (Grok)"
        case .higgsfield: "Higgsfield"
        case .anthropicWeb: "Anthropic Console"
        case .openAIWeb: "OpenAI Platform"
        case .googleAIStudio: "Google AI Studio"
        case .huggingFace: "Hugging Face"
        case .replicateWeb: "Replicate"
        case .github: "GitHub"
        case .gitlab: "GitLab"
        case .cloudflareAPI: "Cloudflare API"
        case .cloudflareAccount: "Cloudflare Account"
        case .tailscale: "Tailscale"
        case .discord: "Discord"
        case .slack: "Slack"
        case .qiita: "Qiita"
        }
    }

    var envVarName: String {
        switch self {
        case .anthropic: "ANTHROPIC_API_KEY"
        case .openAI: "OPENAI_API_KEY"
        case .xAI: "XAI_API_KEY"
        case .higgsfield: "HIGGSFIELD_API_KEY"
        case .anthropicWeb: "ANTHROPIC_WEB_AUTH"
        case .openAIWeb: "OPENAI_WEB_AUTH"
        case .googleAIStudio: "GOOGLE_AI_WEB_AUTH"
        case .huggingFace: "HUGGINGFACE_TOKEN"
        case .replicateWeb: "REPLICATE_API_TOKEN"
        case .github: "GITHUB_TOKEN"
        case .gitlab: "GITLAB_TOKEN"
        case .cloudflareAPI: "CLOUDFLARE_API_TOKEN"
        case .cloudflareAccount: "CLOUDFLARE_ACCOUNT_ID"
        case .tailscale: "TAILSCALE_AUTH_KEY"
        case .discord: "DISCORD_TOKEN"
        case .slack: "SLACK_APP_TOKEN"
        case .qiita: "QIITA_TOKEN"
        }
    }

    var category: KeyCategory {
        switch self {
        case .anthropic, .openAI, .xAI, .higgsfield: .ai
        case .anthropicWeb, .openAIWeb, .googleAIStudio, .huggingFace, .replicateWeb: .webAuth
        case .github, .gitlab: .codeAndGit
        case .cloudflareAPI, .cloudflareAccount, .tailscale: .cloud
        case .discord, .slack: .communication
        case .qiita: .devTools
        }
    }

    /// Web認証情報かどうか
    var isWebAuth: Bool { category == .webAuth }

    /// Web認証のログインURL
    var loginURL: URL? {
        switch self {
        case .anthropicWeb: URL(string: "https://console.anthropic.com/login")
        case .openAIWeb: URL(string: "https://platform.openai.com/login")
        case .googleAIStudio: URL(string: "https://aistudio.google.com/")
        case .huggingFace: URL(string: "https://huggingface.co/login")
        case .replicateWeb: URL(string: "https://replicate.com/signin")
        default: nil
        }
    }

    var tokenPrefix: String? {
        switch self {
        case .anthropic: "sk-ant-"
        case .openAI: "sk-"
        case .xAI: "xai-"
        case .github: "ghp_"
        case .gitlab: "glpat-"
        case .tailscale: "tskey-"
        case .slack: "xapp-"
        case .huggingFace: "hf_"
        case .replicateWeb: "r8_"
        default: nil
        }
    }

    var setupURL: URL? {
        switch self {
        case .anthropic: URL(string: "https://console.anthropic.com/settings/keys")
        case .openAI: URL(string: "https://platform.openai.com/api-keys")
        case .xAI: URL(string: "https://console.x.ai/")
        case .higgsfield: URL(string: "https://higgsfield.ai/")
        case .anthropicWeb: URL(string: "https://console.anthropic.com/")
        case .openAIWeb: URL(string: "https://platform.openai.com/")
        case .googleAIStudio: URL(string: "https://aistudio.google.com/apikey")
        case .huggingFace: URL(string: "https://huggingface.co/settings/tokens")
        case .replicateWeb: URL(string: "https://replicate.com/account/api-tokens")
        case .github: URL(string: "https://github.com/settings/tokens")
        case .gitlab: URL(string: "https://gitlab.com/-/user_settings/personal_access_tokens")
        case .cloudflareAPI: URL(string: "https://dash.cloudflare.com/profile/api-tokens")
        case .cloudflareAccount: URL(string: "https://dash.cloudflare.com/")
        case .tailscale: URL(string: "https://login.tailscale.com/admin/settings/keys")
        case .discord: URL(string: "https://discord.com/developers/applications")
        case .slack: URL(string: "https://api.slack.com/apps")
        case .qiita: URL(string: "https://qiita.com/settings/tokens/new")
        }
    }

    var systemImage: String {
        switch self {
        case .anthropic: "brain"
        case .openAI: "sparkles"
        case .xAI: "bolt.fill"
        case .higgsfield: "waveform"
        case .anthropicWeb: "globe"
        case .openAIWeb: "globe"
        case .googleAIStudio: "globe"
        case .huggingFace: "face.smiling"
        case .replicateWeb: "globe"
        case .github: "chevron.left.forwardslash.chevron.right"
        case .gitlab: "chevron.left.forwardslash.chevron.right"
        case .cloudflareAPI, .cloudflareAccount: "cloud.fill"
        case .tailscale: "network"
        case .discord: "message.fill"
        case .slack: "number"
        case .qiita: "doc.text"
        }
    }
}
