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

function countOccurrences(haystack, needle) {
  let count = 0;
  let idx = haystack.indexOf(needle);
  while (idx !== -1) {
    count++;
    idx = haystack.indexOf(needle, idx + needle.length);
  }
  return count;
}

/** Remove every complete BEGIN..END block (assumes balanced, non-overlapping markers). */
function removeCompleteBlocks(content) {
  let result = content;
  let beginIdx = result.indexOf(BLOCK_BEGIN);
  while (beginIdx !== -1) {
    const endIdx = result.indexOf(BLOCK_END, beginIdx);
    if (endIdx === -1) break; // shouldn't happen when markers are balanced
    result = result.slice(0, beginIdx) + result.slice(endIdx + BLOCK_END.length);
    beginIdx = result.indexOf(BLOCK_BEGIN);
  }
  return result;
}

/**
 * Insert or replace the managed block in `content`. Idempotent and
 * non-destructive:
 *  - no block         → append one
 *  - one+ complete blocks → canonicalize to exactly one (dedupes duplicates)
 *  - unbalanced markers (dangling BEGIN/END from hand-editing) → refuse to edit
 *    so no user content is ever truncated.
 * Returns { content, action: 'created' | 'updated' | 'unchanged' | 'malformed' }.
 */
export function upsertManagedBlock(content) {
  const block = renderManagedBlock();
  const existing = content ?? '';

  const begins = countOccurrences(existing, BLOCK_BEGIN);
  const ends = countOccurrences(existing, BLOCK_END);

  if (begins !== ends) {
    // Malformed (e.g. a dangling BEGIN with no END). Do not guess where the
    // block ends — leave the file untouched and let the caller warn.
    return { content: existing, action: 'malformed' };
  }

  if (begins === 0) {
    const sep = existing.length === 0 ? '' : existing.endsWith('\n') ? '\n' : '\n\n';
    return { content: `${existing}${sep}${block}\n`, action: 'created' };
  }

  // Remove all existing blocks, tidy whitespace, then append exactly one.
  const stripped = removeCompleteBlocks(existing).replace(/\n{3,}/g, '\n\n').replace(/\s+$/, '');
  const next = stripped.length === 0 ? `${block}\n` : `${stripped}\n\n${block}\n`;
  return { content: next, action: next === existing ? 'unchanged' : 'updated' };
}
