# aikeychain

**CLI & MCP server for [AI KeyChain](https://github.com/aieo-product/AIkeychain)** — use API keys stored in the macOS Keychain without ever writing them to `.env` files, shell config, or code. Works standalone (no GUI app required).

```bash
npm install -g aikeychain   # or use npx aikeychain
```

> macOS only (uses the `security` command). Node.js 18+.

## Why

AI agents (Claude, Codex, ...) and humans keep mishandling secrets: pasting them into `.env`, hardcoding them, or reading the Keychain the wrong way. `akc` gives both a safe, uniform interface:

- Env vars hold **references** (`keychain://KEY_NAME`), never values
- `akc run` resolves references and injects real values **only into the child process**
- The bundled **MCP server** teaches AI agents the correct usage and never returns raw secret values to the model

## CLI

```bash
# Run anything with secrets injected (parent env never sees values)
export OPENAI_API_KEY=keychain://OPENAI_API_KEY
akc run -- claude

# Preview what would resolve (values masked)
akc run --dry-run

# Manage keys
akc list                  # key names only — never prints values
akc check GITHUB_TOKEN    # exists? in which store?
akc get GITHUB_TOKEN      # prints keychain://GITHUB_TOKEN (use --reveal for the raw value)
akc set GITHUB_TOKEN      # hidden prompt (or pipe via stdin); overwrites in place, no duplicates
akc delete GITHUB_TOKEN

# Diagnose your setup (env + ~/.zshrc), including the -a "$USER" pitfall
akc doctor

# Print the usage guide for AI agents
akc guide
```

### Keychain lookup order

1. `service="com.aieo.aikeychain"`, `account=<KEY>` — the AI KeyChain GUI store
2. `service=<KEY>` with **no account** — manually-registered keys

Manual keys are looked up by service only because `acct` attributes are inconsistent across entries; pinning `-a` can return a stale duplicate ([issue #91](https://github.com/aieo-product/AIkeychain/issues/91)).

## MCP server

```bash
# Claude Code
claude mcp add aikeychain -- npx -y aikeychain mcp

# Codex CLI (~/.codex/config.toml)
# [mcp_servers.aikeychain]
# command = "npx"
# args = ["-y", "aikeychain", "mcp"]
```

| Tool | Returns | Raw secret exposed to model? |
|---|---|---|
| `usage_guide` | How to handle secrets on this machine | No |
| `list_keys` | Key names + which store | No |
| `check_key` | Existence + store | No |
| `get_secret_reference` | `keychain://KEY` + usage snippet | No |
| `set_secret` | Save confirmation | Input only (prefer `akc set` by the user) |
| `delete_secret` | Deletion result (requires `confirm: true`) | No |
| `doctor` | Masked diagnosis of env + shell config | No |

**There is intentionally no tool that returns a secret value.** Agents obtain a `keychain://` reference and execute workloads through `akc run`, so values stay out of the model context entirely.

## License

MIT
