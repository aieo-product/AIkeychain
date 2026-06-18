// `akc init` — one-command discoverability setup so AI agents (and humans) learn
// how to use AI KeyChain:
//   1. Write a managed instructions block into CLAUDE.md and AGENTS.md (idempotent).
//   2. Register the MCP server with Claude Code (`claude mcp add`) when available.
//   3. Print the Codex config snippet and next steps.

import { readFile, writeFile } from 'node:fs/promises';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { renderManagedBlock, upsertManagedBlock } from './agent-setup.js';

const pExecFile = promisify(execFile);

const CODEX_SNIPPET = `[mcp_servers.aikeychain]
command = "akc"
args = ["mcp"]`;

async function writeBlock(path) {
  let existing = '';
  try {
    existing = await readFile(path, 'utf8');
  } catch {
    existing = '';
  }
  const { content, action } = upsertManagedBlock(existing);
  if (action !== 'unchanged') {
    await writeFile(path, content);
  }
  return { path, action };
}

async function registerClaudeMcp() {
  // Idempotent-ish: remove any prior registration, then add. Tolerate failures.
  try {
    await pExecFile('claude', ['mcp', 'remove', 'aikeychain'], { timeout: 15000 });
  } catch {
    // not registered yet, or claude missing — fall through to add
  }
  await pExecFile('claude', ['mcp', 'add', 'aikeychain', '--', 'akc', 'mcp'], { timeout: 15000 });
}

export async function cmdInit(argv) {
  const printOnly = argv.includes('--print');
  const noRegister = argv.includes('--no-register');
  const global = argv.includes('--global');

  const out = process.stdout;

  if (printOnly) {
    out.write('# Managed block that `akc init` writes to CLAUDE.md / AGENTS.md:\n\n');
    out.write(`${renderManagedBlock()}\n\n`);
    out.write('# Claude Code MCP registration:\n');
    out.write('  claude mcp add aikeychain -- akc mcp\n\n');
    out.write('# Codex (~/.codex/config.toml):\n');
    out.write(`${CODEX_SNIPPET}\n`);
    return 0;
  }

  // 1. Instructions files
  const targets = global
    ? [join(homedir(), '.claude', 'CLAUDE.md')]
    : [join(process.cwd(), 'CLAUDE.md'), join(process.cwd(), 'AGENTS.md')];

  for (const path of targets) {
    try {
      const { action } = await writeBlock(path);
      const verb = { created: 'wrote', updated: 'updated', unchanged: 'already current' }[action];
      out.write(`  ✅ ${verb}: ${path}\n`);
    } catch (err) {
      out.write(`  ⚠️  could not write ${path}: ${err.message}\n`);
    }
  }

  // 2. Claude Code MCP registration
  if (noRegister) {
    out.write('  ⏭️  skipped MCP registration (--no-register)\n');
  } else {
    try {
      await registerClaudeMcp();
      out.write('  ✅ registered MCP server with Claude Code (aikeychain)\n');
    } catch {
      out.write('  ⏭️  Claude Code CLI not found — register manually:\n');
      out.write('       claude mcp add aikeychain -- akc mcp\n');
    }
  }

  // 3. Codex + next steps
  out.write('\nFor Codex, add to ~/.codex/config.toml:\n');
  out.write(`${CODEX_SNIPPET.split('\n').map((l) => `  ${l}`).join('\n')}\n`);
  out.write('\nDone. New AI sessions will discover AI KeyChain via the MCP tools and the\n');
  out.write('instructions block. Run `akc guide` anytime for the full usage guide.\n');
  return 0;
}
