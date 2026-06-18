// Shared content + helpers for `akc init`: a managed instructions block that
// teaches AI agents (Claude, Codex, ...) how to use AI KeyChain, plus an
// idempotent upsert so re-running init never duplicates the block.

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

/**
 * Insert or replace the managed block in `content`. Idempotent: re-running
 * replaces the existing block in place rather than appending a duplicate.
 * Returns { content, action: 'created' | 'updated' | 'unchanged' }.
 */
export function upsertManagedBlock(content) {
  const block = renderManagedBlock();
  const existing = content ?? '';
  const beginIdx = existing.indexOf(BLOCK_BEGIN);

  if (beginIdx === -1) {
    // Append, separated by a blank line from any prior content.
    const sep = existing.length === 0 ? '' : existing.endsWith('\n') ? '\n' : '\n\n';
    return { content: `${existing}${sep}${block}\n`, action: 'created' };
  }

  const endIdx = existing.indexOf(BLOCK_END, beginIdx);
  if (endIdx === -1) {
    // Begin marker without a matching end (hand-edited): replace from begin to EOF.
    return { content: `${existing.slice(0, beginIdx)}${block}\n`, action: 'updated' };
  }

  const before = existing.slice(0, beginIdx);
  const after = existing.slice(endIdx + BLOCK_END.length);
  const next = `${before}${block}${after}`;
  if (next === existing) {
    return { content: existing, action: 'unchanged' };
  }
  return { content: next, action: 'updated' };
}
