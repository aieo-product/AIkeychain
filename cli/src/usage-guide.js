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
3. To check/read a key, prefer \`akc get <KEY>\`: by default it prints only the
   keychain:// reference (never the value). Add --reveal only when you truly
   need the raw value on stdout; to inject it into a process instead, use
   \`akc run -- <command>\`. If you must use the raw security CLI directly:
       /usr/bin/security find-generic-password -s "com.aieo.aikeychain.managed" -a "<KEY>" -w
   ⚠️ The bare -s "<KEY>" form (no -a) returns "could not be found" (exit 44) —
   that is NOT proof the key is unregistered. Confirm with \`akc check <KEY>\` /
   \`akc get <KEY>\`.
4. To save/update a key, use \`akc set KEY_NAME\`: it writes to the managed
   namespace with -U (no duplicate entries), and the value is read from a
   hidden prompt or stdin and handed to \`security -i\` via stdin as hex — it
   never appears in any process's argv, shell history, or logs. Do NOT invent
   your own \`security add-generic-password\` invocation: a -w "<value>" form
   leaks the secret into argv/shell history, and writing to any other service
   name creates entries outside the managed namespace.
   Value constraints: printable ASCII, single line, at most
   floor((4094 - 66 - key name length) / 2) ≈ 2,000 characters (the \`security -i\`
   line budget; hex is kept as the injection guard). Longer, multi-line or
   non-ASCII values are not supported.

## Headless contract (what akc promises)

Every key lives in the **managed namespace** (\`com.aieo.aikeychain.managed\`,
created by \`akc set\` or the AI KeyChain app). These resolve **silently** — no
prompts, no hangs, ever. (v2.0 dropped the old v1.x GUI store / manual scheme;
if you upgraded from v1.x, bulk-migrate with \`akc migrate\` or re-register
with \`akc set <KEY>\`.)

## Where keys live

| Store | service attribute | account attribute |
|---|---|---|
| Managed namespace (the only store) | com.aieo.aikeychain.managed | <KEY_NAME> |

## CLI quick reference

  akc run -- <command>        run a command with keychain:// refs resolved
  akc run --dry-run           show which env vars would resolve (values masked)
  akc list                    list known key names (never prints values)
  akc check <KEY>             check whether a key exists and where
  akc set <KEY>               store/update a key (value via hidden prompt or stdin)
  akc migrate                 bulk-migrate v1.x keys into the managed namespace
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
