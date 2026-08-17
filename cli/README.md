# aikeychain

**CLI & MCP server for [AI KeyChain](https://github.com/aieo-product/AIkeychain)** — use API keys stored in the macOS Keychain without ever writing them to `.env` files, shell config, or code. Works standalone (no GUI app required).

```bash
npm install -g aikeychain   # or use npx aikeychain
akc init                    # teach the AI agents on this machine to use it
```

> macOS only (uses the `security` command). Node.js 18+.

### Supply-chain hardening (optional)

`aikeychain` ships an `npm-shrinkwrap.json` so `npm install -g` resolves the exact,
integrity-checked dependency tree that was tested and published — not a floating
range. This package defines no `preinstall`/`postinstall`/`prepare` scripts, so you
can additionally install with scripts disabled for defense-in-depth against a
compromised transitive dependency:

```bash
npm install -g aikeychain --ignore-scripts
```

## For AI agents (Claude, Codex, …)

Run **`akc init`** once. It sets up **every AI session on this machine** (AI KeyChain is not a per-project tool):

1. Writes a managed instructions block into `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md` (idempotent) so agents learn the rules.
2. Registers the MCP server with Claude Code at **user scope** (`claude mcp add --scope user aikeychain -- akc mcp`) — every project/session sees it.
3. Adds the MCP server to `~/.codex/config.toml` for Codex.

After that, every new Claude/Codex session discovers AI KeyChain via the MCP tools (`usage_guide`, `list_keys`, `get_secret_reference`, …) and the instructions block — no per-session setup. (Already-running sessions need a restart.)

Flags: `--print` previews without writing, `--no-register` skips MCP registration, `--local` scopes everything to the current project (`./CLAUDE.md` + `./AGENTS.md` + a local-scope Claude MCP) instead of machine-wide.

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
akc set GITHUB_TOKEN      # hidden prompt (or pipe via stdin); the value never
                          # appears in any process's argv — fed to `security -i`
                          # via stdin as hex. Overwrites in place, no duplicates
akc delete GITHUB_TOKEN

# Diagnose your setup: keychain access + keychain:// references in env and ~/.zshrc
akc doctor

# Print the usage guide for AI agents
akc guide
```

### Keychain lookup (v2.0)

Every key lives at `service="com.aieo.aikeychain.managed"`, `account=<KEY>` — the
single managed namespace, created by `/usr/bin/security` so headless reads never
prompt. The old v1.x GUI store / manual scheme are no longer read; upgrading users
re-register their keys with `akc set <KEY>`.

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

## Trademarks

This is an independent project and is **not affiliated with, endorsed by, or sponsored by Apple Inc.** "Apple", "macOS", and "Keychain" are trademarks of Apple Inc., used here for descriptive and identification purposes only.

## License

MIT
