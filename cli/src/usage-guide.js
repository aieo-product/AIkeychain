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
3. To check/read a key, prefer \`akc get <KEY>\`: it checks both stores and by
   default prints only the keychain:// reference (never the value). Add
   --reveal only when you truly need the raw value on stdout; to inject it into
   a process instead, use \`akc run -- <command>\`. If you must use the raw
   security CLI directly, use the form that matches where the key lives:
     [managed] keys (saved by akc or the AI KeyChain GUI, v1.9+):
       /usr/bin/security find-generic-password -s "com.aieo.aikeychain.managed" -a "<KEY>" -w
     [app] legacy store keys (saved via an older AI KeyChain GUI):
       /usr/bin/security find-generic-password -s "com.aieo.aikeychain" -a "<KEY>" -w
     [manual] legacy keys (registered by hand) — service name only, do NOT pin
     the account with -a "$USER":
       /usr/bin/security find-generic-password -s "<KEY>" -w
   ⚠️ The bare -s "<KEY>" form (no -a) returns "could not be found" (exit 44)
   for [managed]/[app] keys — that is NOT proof the key is unregistered.
   Confirm with \`akc check <KEY>\` / \`akc get <KEY>\` before concluding a key
   is missing. (Account attributes on [manual] entries are inconsistent across
   entries; pinning -a there can return a stale/invalid duplicate — AIkeychain
   issue #91.)
4. To save/update a key, use \`akc set KEY_NAME\`: it writes to the managed
   namespace with -U (no duplicate entries), and the value is read from a
   hidden prompt or stdin and handed to \`security -i\` via stdin as hex — it
   never appears in any process's argv, shell history, or logs. Do NOT invent
   your own \`security add-generic-password\` invocation: a -w "<value>" form
   leaks the secret into argv/shell history, and writing to any other service
   name creates entries outside the managed namespace.

## Headless contract (what akc promises)

- Keys in the **managed namespace** (saved by \`akc set\` or the AI KeyChain app
  v1.9+) resolve **silently** — no prompts, no hangs, ever.
- **Legacy keys** (old GUI store / manually registered) may be readable, but a
  GUI-owned item can block on a keychain consent prompt. akc **never hangs**:
  the read is killed after a timeout and you get an explicit
  "migration required" error telling you to re-register the key
  (\`akc set <KEY>\`) or use the app's migration assistant.
- The promise is "new/migrated keys succeed silently; legacy keys fail bounded"
  — NOT "mixed stores always succeed". Run \`akc doctor\` to list unmigrated
  keys before relying on headless execution.

## Where keys live

| Store | service attribute | account attribute |
|---|---|---|
| Managed namespace (v1.9+, all new writes) | com.aieo.aikeychain.managed | <KEY_NAME> |
| AI KeyChain GUI store (legacy, read-only) | com.aieo.aikeychain | <KEY_NAME> |
| Manually-registered keys (legacy, read-only) | <KEY_NAME> | (varies — do not rely on it) |

\`akc\` looks up managed first, then the legacy GUI store, then the service-only
manual lookup — falling through ONLY when a tier reports "not found" (exit 44).

## CLI quick reference

  akc run -- <command>        run a command with keychain:// refs resolved
  akc run --dry-run           show which env vars would resolve (values masked)
  akc list                    list known key names (never prints values)
  akc check <KEY>             check whether a key exists and where
  akc set <KEY>               store/update a key (value via hidden prompt or stdin)
  akc delete <KEY>            delete a key
  akc doctor                  diagnose env + ~/.zshrc refs + unmigrated legacy keys
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
