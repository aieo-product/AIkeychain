// Canonical "how to use AI KeyChain correctly" guide, exposed to AI agents via
// the `usage_guide` MCP tool and `akc guide`. This is the single place where
// the rules live so every model/session gets the same instructions.

export const USAGE_GUIDE = `# AI KeyChain — usage guide for AI agents and humans

AI KeyChain stores API keys/tokens in the macOS Keychain (encrypted at rest).
Secrets must NEVER be written to .env files, shell scripts, code, or commits.

## The golden rules

1. NEVER write a secret value into a file (.env, .zshrc, source code, logs).
2. To use secrets in a process, prefer keychain:// references + \`akc run\`:
   - Set env vars to a reference, not a value:  export OPENAI_API_KEY=keychain://OPENAI_API_KEY
   - Launch tools through akc:                  akc run -- <command>
   - akc resolves the references from the macOS Keychain and injects the real
     values ONLY into the child process. The parent shell never sees them.
3. To read a key manually, prefer \`akc get <KEY>\`: it checks both stores and
   never exposes the value beyond the child process. If you must use the raw
   security CLI directly, use the form that matches where the key lives:
     [app] store keys (saved via the AI KeyChain GUI):
       security find-generic-password -s "com.aieo.aikeychain" -a "<KEY>" -w
     [manual] keys (registered by hand) — service name only, do NOT pin the
     account with -a "$USER":
       security find-generic-password -s "<KEY>" -w
   ⚠️ The bare -s "<KEY>" form (no -a) returns "could not be found" (exit 44)
   for [app] store keys — that is NOT proof the key is unregistered. Confirm
   with \`akc check <KEY>\` / \`akc get <KEY>\` before concluding a key is
   missing. (Account attributes on [manual] entries are inconsistent across
   entries; pinning -a there can return a stale/invalid duplicate — AIkeychain
   issue #91.)
4. To save/update a key, overwrite with -U so no duplicate entries are created:
     security add-generic-password -s "KEY_NAME" -a "KEY_NAME" -w "<value>" -U
   (prefer \`akc set KEY_NAME\`: the value is read from a hidden prompt or stdin
   and handed to \`security -i\` via stdin as hex — it never appears in any
   process's argv, shell history, or logs.)

## Where keys live

| Store | service attribute | account attribute |
|---|---|---|
| AI KeyChain GUI store | com.aieo.aikeychain | <KEY_NAME> |
| Manually-registered keys | <KEY_NAME> | (varies — do not rely on it) |

\`akc\` looks up the GUI store first, then falls back to service-only lookup.

## CLI quick reference

  akc run -- <command>        run a command with keychain:// refs resolved
  akc run --dry-run           show which env vars would resolve (values masked)
  akc list                    list known key names (never prints values)
  akc check <KEY>             check whether a key exists and where
  akc set <KEY>               store/update a key (value via hidden prompt or stdin)
  akc delete <KEY>            delete a key
  akc doctor                  diagnose env + ~/.zshrc keychain references
  akc mcp                     start the MCP server (stdio)

## MCP setup (Claude Code)

  claude mcp add aikeychain -- npx -y aikeychain mcp

The MCP tools intentionally never return raw secret values to the model.
Get a keychain:// reference with get_secret_reference, then run the actual
workload through \`akc run\` so values stay out of the model context.

## Three modes of AI KeyChain (GUI app)

- Standard:        keys exported in .zshrc via security find-generic-password
- Secret Reference: keychain:// refs + akc run (recommended for AI agents)
- Proxy:           local proxy injects auth headers; keys never enter env
`;
