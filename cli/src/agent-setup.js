// Shared content + helpers for `akc init`: a managed instructions block that
// teaches AI agents (Claude, Codex, ...) how to use AI KeyChain, plus an
// idempotent upsert so re-running init never duplicates the block.

import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

export const BLOCK_BEGIN = '<!-- BEGIN aikeychain (managed by `akc init`) -->';
export const BLOCK_END = '<!-- END aikeychain (managed by `akc init`) -->';

/** The instructions injected into CLAUDE.md / AGENTS.md. Single source of the rules. */
export const AGENT_INSTRUCTIONS = `## Secrets: use AI KeyChain (\`akc\`)

API keys/tokens live in the **macOS Keychain**, not in files. NEVER write a secret
value into \`.env\`, source code, logs, or commits.

- Run tools with secrets injected, without exposing values:
  \`\`\`bash
  export OPENAI_API_KEY=keychain://OPENAI_API_KEY
  akc run -- <command>            # resolves keychain:// refs into the child process only
  \`\`\`
- Read a key manually by **service name only** — do NOT pin \`-a "$USER"\`
  (account attributes are inconsistent; pinning can return a stale value):
  \`\`\`bash
  security find-generic-password -s "ENV_VAR_NAME" -w
  \`\`\`
- Store/update a key without exposing it in argv or shell history:
  \`\`\`bash
  akc set ENV_VAR_NAME          # hidden prompt (or pipe via stdin)
  \`\`\`
- Other commands: \`akc list\` / \`akc check <KEY>\` / \`akc get <KEY>\` / \`akc doctor\`.
  Run \`akc guide\` for the full guide.

If an \`aikeychain\` MCP server is available, call its \`usage_guide\` tool first, and
use \`get_secret_reference\` + \`akc run\` so secret values never enter the model context.`;

/** Render the full managed block (markers + instructions). */
export function renderManagedBlock() {
  return `${BLOCK_BEGIN}\n${AGENT_INSTRUCTIONS}\n${BLOCK_END}`;
}

function countOccurrences(haystack, needle) {
  let count = 0;
  let idx = haystack.indexOf(needle);
  while (idx !== -1) {
    count++;
    idx = haystack.indexOf(needle, idx + needle.length);
  }
  return count;
}

/** Remove every complete begin..end block (assumes balanced, non-overlapping markers). */
function removeCompleteBlocks(content, begin, end) {
  let result = content;
  let beginIdx = result.indexOf(begin);
  while (beginIdx !== -1) {
    const endIdx = result.indexOf(end, beginIdx);
    if (endIdx === -1) break; // shouldn't happen when markers are balanced
    result = result.slice(0, beginIdx) + result.slice(endIdx + end.length);
    beginIdx = result.indexOf(begin);
  }
  return result;
}

/**
 * Insert or replace a marker-delimited block in `content`. Idempotent and
 * non-destructive:
 *  - no block          → append one
 *  - one+ complete blocks → canonicalize to exactly one (dedupes duplicates)
 *  - unbalanced markers (dangling begin/end) → refuse to edit (no truncation)
 * Returns { content, action: 'created' | 'updated' | 'unchanged' | 'malformed' }.
 */
export function upsertDelimitedBlock(content, begin, end, fullBlock) {
  const existing = content ?? '';
  const begins = countOccurrences(existing, begin);
  const ends = countOccurrences(existing, end);

  if (begins !== ends) {
    return { content: existing, action: 'malformed' };
  }

  if (begins === 0) {
    const sep = existing.length === 0 ? '' : existing.endsWith('\n') ? '\n' : '\n\n';
    return { content: `${existing}${sep}${fullBlock}\n`, action: 'created' };
  }

  const stripped = removeCompleteBlocks(existing, begin, end)
    .replace(/\n{3,}/g, '\n\n')
    .replace(/\s+$/, '');
  const next = stripped.length === 0 ? `${fullBlock}\n` : `${stripped}\n\n${fullBlock}\n`;
  return { content: next, action: next === existing ? 'unchanged' : 'updated' };
}

/** Upsert the markdown instructions block (CLAUDE.md / AGENTS.md). */
export function upsertManagedBlock(content) {
  return upsertDelimitedBlock(content, BLOCK_BEGIN, BLOCK_END, renderManagedBlock());
}

// --- PATH-independent MCP launch resolution (issue #131) ---
//
// `akc init` used to register the aikeychain MCP server with the bare
// command name `akc`. That relies on PATH lookup at spawn time — but MCP
// servers are frequently spawned from environments that don't source the
// user's shell rc (GUI apps, cron, launchd) or after a Node version switch
// (nvm) moved `akc` to a different bin directory. Result: the server fails to
// launch silently and AI sessions can't discover AI KeyChain.
//
// Resolving an absolute path to the Node binary that's *currently running
// this process* (`process.execPath`) and to this package's own `bin/akc.js`
// makes the registration PATH-independent: it works from any environment,
// with any PATH (even `env -i`), as long as those two files still exist.

/**
 * Resolve absolute, PATH-independent launch info for this akc install: the
 * node binary running this process, and this package's bin/akc.js.
 * Returns null if resolution fails (e.g. an unexpected package layout) —
 * callers should fall back to the bare `akc` command in that case.
 */
export function resolveAkcLaunch() {
  try {
    const nodeBin = process.execPath;
    // This file lives at <package root>/src/agent-setup.js.
    const here = dirname(fileURLToPath(import.meta.url));
    const akcJs = join(here, '..', 'bin', 'akc.js');
    if (nodeBin && existsSync(nodeBin) && existsSync(akcJs)) {
      return { nodeBin, akcJs };
    }
  } catch {
    // fall through
  }
  return null;
}

/** Quote a value for safe inclusion in a POSIX shell command line (copy-paste display only). */
export function shellQuote(value) {
  if (/^[A-Za-z0-9_./-]+$/.test(value)) return value;
  return `'${value.replace(/'/g, "'\\''")}'`;
}

/** Escape a value for inclusion in a TOML basic string ("..."). */
function tomlEscape(value) {
  return value.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
}

// --- Codex MCP server block (~/.codex/config.toml) ---
// Markers are TOML comments so the block is valid TOML.
export const CODEX_BLOCK_BEGIN = '# BEGIN aikeychain (managed by `akc init`)';
export const CODEX_BLOCK_END = '# END aikeychain (managed by `akc init`)';

/**
 * Render the Codex MCP block. When `launch` (from resolveAkcLaunch) is
 * given, registers with absolute paths (PATH-independent); otherwise falls
 * back to the bare `akc` command.
 */
export function renderCodexBlock(launch) {
  if (launch) {
    const command = tomlEscape(launch.nodeBin);
    const akcJs = tomlEscape(launch.akcJs);
    return (
      `${CODEX_BLOCK_BEGIN}\n` +
      '# Absolute paths — PATH-independent launch (issue #131). If Node was\n' +
      '# upgraded/reinstalled, re-run `akc init` to refresh these paths.\n' +
      '[mcp_servers.aikeychain]\n' +
      `command = "${command}"\n` +
      `args = ["${akcJs}", "mcp"]\n` +
      `${CODEX_BLOCK_END}`
    );
  }
  return `${CODEX_BLOCK_BEGIN}\n[mcp_servers.aikeychain]\ncommand = "akc"\nargs = ["mcp"]\n${CODEX_BLOCK_END}`;
}

/**
 * Ensure the Codex MCP block is present in a config.toml. Append-only and
 * idempotent: if the marker is already there it leaves the file completely
 * untouched (never reformats the user's hand-written TOML).
 * Returns { content, action: 'created' | 'unchanged' }.
 */
export function upsertCodexBlock(content, launch) {
  const existing = content ?? '';
  if (existing.includes(CODEX_BLOCK_BEGIN)) {
    return { content: existing, action: 'unchanged' };
  }
  // A hand-written [mcp_servers.aikeychain] table (without our markers) would
  // become a duplicate table key — invalid TOML — if we appended ours. Refuse
  // and let the caller tell the user to merge manually.
  if (/^\s*\[mcp_servers\.aikeychain\]\s*$/m.test(existing)) {
    return { content: existing, action: 'conflict' };
  }
  const sep = existing.length === 0 ? '' : existing.endsWith('\n') ? '\n' : '\n\n';
  return { content: `${existing}${sep}${renderCodexBlock(launch)}\n`, action: 'created' };
}
