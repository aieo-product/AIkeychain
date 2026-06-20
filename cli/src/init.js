// `akc init` — one-command discoverability setup so AI agents (and humans) learn
// how to use AI KeyChain. Machine-wide by default (this tool is not meant to be
// scoped per project):
//   - Claude: write ~/.claude/CLAUDE.md + register the MCP server at user scope
//   - Codex:  write ~/.codex/AGENTS.md + add the MCP server to ~/.codex/config.toml
// Use --local for the old project-scoped behavior (./CLAUDE.md + ./AGENTS.md and a
// local-scope Claude MCP registration).

import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { homedir } from 'node:os';
import { join, dirname } from 'node:path';
import {
  renderManagedBlock,
  renderCodexBlock,
  upsertManagedBlock,
  upsertCodexBlock,
} from './agent-setup.js';

const pExecFile = promisify(execFile);

async function readFileOrEmpty(path) {
  try {
    return await readFile(path, 'utf8');
  } catch (err) {
    // Only "missing" means start fresh; surface other errors (e.g. permissions).
    if (err.code === 'ENOENT') return '';
    throw err;
  }
}

/** Apply an upsert result to a file, creating parent dirs as needed. */
async function applyUpsert(path, upsert) {
  const existing = await readFileOrEmpty(path);
  const { content, action } = upsert(existing);
  if (action !== 'unchanged' && action !== 'malformed') {
    await mkdir(dirname(path), { recursive: true });
    await writeFile(path, content);
  }
  return action;
}

async function registerClaudeMcp(scope) {
  const addArgs = ['mcp', 'add', '--scope', scope, 'aikeychain', '--', 'akc', 'mcp'];
  // Add first; only replace (remove+add) if the add fails (usually "exists"),
  // so a working registration is never deleted unless we are re-adding it.
  try {
    await pExecFile('claude', addArgs, { timeout: 15000 });
    return;
  } catch {
    // already registered or transient failure
  }
  try {
    await pExecFile('claude', ['mcp', 'remove', '--scope', scope, 'aikeychain'], { timeout: 15000 });
  } catch {
    try {
      await pExecFile('claude', ['mcp', 'remove', 'aikeychain'], { timeout: 15000 });
    } catch {
      // ignore — the add below will surface a real failure
    }
  }
  await pExecFile('claude', addArgs, { timeout: 15000 });
}

function reportAction(out, path, action) {
  if (action === 'malformed') {
    out.write(`  ⚠️  ${path} has unbalanced aikeychain markers — left untouched. Fix it manually, then re-run.\n`);
    return true; // failure
  }
  const verb = { created: 'wrote', updated: 'updated', unchanged: 'already current' }[action];
  out.write(`  ✅ ${verb}: ${path}\n`);
  return false;
}

export async function cmdInit(argv) {
  const printOnly = argv.includes('--print');
  const noRegister = argv.includes('--no-register');
  const local = argv.includes('--local');
  const out = process.stdout;

  if (printOnly) {
    out.write('# Instructions block written to CLAUDE.md / AGENTS.md:\n\n');
    out.write(`${renderManagedBlock()}\n\n`);
    out.write('# Claude Code MCP registration (machine-wide):\n');
    out.write('  claude mcp add --scope user aikeychain -- akc mcp\n\n');
    out.write('# Codex block appended to ~/.codex/config.toml:\n');
    out.write(`${renderCodexBlock()}\n`);
    return 0;
  }

  let failed = false;
  const home = homedir();

  if (local) {
    // Project-scoped (legacy): files in cwd, Claude MCP at local scope.
    for (const path of [join(process.cwd(), 'CLAUDE.md'), join(process.cwd(), 'AGENTS.md')]) {
      try {
        failed = reportAction(out, path, await applyUpsert(path, upsertManagedBlock)) || failed;
      } catch (err) {
        failed = true;
        out.write(`  ⚠️  could not write ${path}: ${err.message}\n`);
      }
    }
    if (!noRegister) await registerClaude(out, 'local');
  } else {
    // Machine-wide (default).
    const targets = [
      { path: join(home, '.claude', 'CLAUDE.md'), upsert: upsertManagedBlock },
      { path: join(home, '.codex', 'AGENTS.md'), upsert: upsertManagedBlock },
      { path: join(home, '.codex', 'config.toml'), upsert: upsertCodexBlock },
    ];
    for (const { path, upsert } of targets) {
      try {
        failed = reportAction(out, path, await applyUpsert(path, upsert)) || failed;
      } catch (err) {
        failed = true;
        out.write(`  ⚠️  could not write ${path}: ${err.message}\n`);
      }
    }
    if (!noRegister) await registerClaude(out, 'user');
  }

  out.write('\nDone. New AI sessions discover AI KeyChain via the MCP tools and the\n');
  out.write('instructions block. Run `akc guide` anytime for the full usage guide.\n');
  if (!local) {
    out.write('(Already-running sessions need a restart to pick this up.)\n');
  }
  return failed ? 1 : 0;
}

async function registerClaude(out, scope) {
  try {
    await registerClaudeMcp(scope);
    out.write(`  ✅ registered MCP server with Claude Code (aikeychain, ${scope} scope)\n`);
  } catch {
    out.write('  ⏭️  Claude Code CLI not found — register manually:\n');
    out.write(`       claude mcp add --scope ${scope} aikeychain -- akc mcp\n`);
  }
}
