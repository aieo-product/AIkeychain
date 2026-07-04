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
  resolveAkcLaunch,
  shellQuote,
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
  if (action === 'created' || action === 'updated') {
    await mkdir(dirname(path), { recursive: true });
    await writeFile(path, content);
  }
  return action;
}

/** Is the aikeychain MCP server already registered with Claude Code? */
async function claudeMcpRegistered() {
  try {
    // `claude` is invoked by bare name (PATH lookup) intentionally. Unlike
    // `security` (issue #117 / cli/src/keychain.js), no secret is ever passed to
    // it (no secret args, no stdin), so this is not the secret-interception
    // vector #117 closes. Bare lookup is accepted on parity grounds — an
    // attacker who can plant a fake `claude` on PATH already gets code execution
    // the moment the user runs `claude` themselves — and because `claude` has no
    // single stable absolute path (npm-global / Homebrew / ~/.claude/local).
    const { stdout } = await pExecFile('claude', ['mcp', 'list'], { timeout: 15000 });
    return /(^|\n)\s*aikeychain[:\s]/.test(stdout);
  } catch {
    return false;
  }
}

/** Build the launch argv (`command`, then args) for a `claude mcp add -- ...`. */
export function launchArgv(launch) {
  // Prefer an absolute-path launch (issue #131): PATH-independent, works from
  // GUI apps / cron / launchd and survives Node version switches. Fall back to
  // the bare `akc` command only when resolution failed.
  return launch ? [launch.nodeBin, launch.akcJs, 'mcp'] : ['akc', 'mcp'];
}

/**
 * Does an existing `claude mcp get aikeychain` output already describe the
 * desired launch? Every launch token (the node binary, akc.js and `mcp`, or
 * bare `akc mcp`) must appear as a substring. The node bin + akc.js are
 * distinctive absolute paths, so a stale registration (bare `akc`, or an
 * absolute path from an old Node version dir) fails to match and gets replaced.
 */
export function registrationMatches(getOutput, argv) {
  return argv.every((token) => getOutput.includes(token));
}

/** Read the current `claude mcp get aikeychain` output, or null if unregistered / no CLI. */
async function claudeMcpGet() {
  try {
    const { stdout } = await pExecFile('claude', ['mcp', 'get', 'aikeychain'], { timeout: 15000 });
    return stdout;
  } catch {
    return null;
  }
}

async function registerClaudeMcp(scope, launch) {
  const argv = launchArgv(launch);

  // Inspect the current registration. If it already matches the desired launch,
  // keep it. If it exists but differs (bare `akc`, or a stale absolute path
  // after a Node upgrade — the exact population issue #131 targets), it must be
  // replaced: `claude mcp add` refuses to overwrite an existing name, so remove
  // first, then re-add.
  const current = await claudeMcpGet();
  if (current !== null && registrationMatches(current, argv)) return; // already current
  if (current !== null) {
    try {
      await pExecFile('claude', ['mcp', 'remove', '--scope', scope, 'aikeychain'], { timeout: 15000 });
    } catch {
      // Removal can fail if the entry lives in a different scope; try add anyway.
    }
  }

  try {
    await pExecFile('claude', ['mcp', 'add', '--scope', scope, 'aikeychain', '--', ...argv], {
      timeout: 15000,
    });
    return;
  } catch {
    // Add failed. Never leave the user unregistered: if *some* registration
    // still exists (e.g. remove failed and add hit "already exists"), keep it.
  }
  if (await claudeMcpRegistered()) return;
  throw new Error('claude mcp add failed and aikeychain is not registered');
}

function reportAction(out, path, action) {
  if (action === 'malformed') {
    out.write(`  ⚠️  ${path} has unbalanced aikeychain markers — left untouched. Fix it manually, then re-run.\n`);
    return true; // failure
  }
  if (action === 'conflict') {
    out.write(`  ⚠️  ${path} already has an [mcp_servers.aikeychain] table without our markers — left untouched. Merge it manually.\n`);
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
  const launch = resolveAkcLaunch();

  if (printOnly) {
    out.write('# Instructions block written to CLAUDE.md / AGENTS.md:\n\n');
    out.write(`${renderManagedBlock()}\n\n`);
    out.write('# Claude Code MCP registration (machine-wide):\n');
    out.write(`  ${claudeAddPreview('user', launch)}\n\n`);
    out.write('# Codex block appended to ~/.codex/config.toml:\n');
    out.write(`${renderCodexBlock(launch)}\n`);
    return 0;
  }

  if (!launch) {
    out.write(
      '  ⚠️  could not resolve an absolute path to this akc install — falling back to the\n' +
        '      bare `akc` command (PATH-dependent; may fail from GUI apps, cron, or after a\n' +
        '      Node version switch). Re-run `akc init` after fixing the install to upgrade.\n'
    );
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
    if (!noRegister) await registerClaude(out, 'local', launch);
  } else {
    // Machine-wide (default).
    const targets = [
      { path: join(home, '.claude', 'CLAUDE.md'), upsert: upsertManagedBlock },
      { path: join(home, '.codex', 'AGENTS.md'), upsert: upsertManagedBlock },
      { path: join(home, '.codex', 'config.toml'), upsert: (content) => upsertCodexBlock(content, launch) },
    ];
    for (const { path, upsert } of targets) {
      try {
        failed = reportAction(out, path, await applyUpsert(path, upsert)) || failed;
      } catch (err) {
        failed = true;
        out.write(`  ⚠️  could not write ${path}: ${err.message}\n`);
      }
    }
    if (!noRegister) await registerClaude(out, 'user', launch);
  }

  out.write('\nDone. New AI sessions discover AI KeyChain via the MCP tools and the\n');
  out.write('instructions block. Run `akc guide` anytime for the full usage guide.\n');
  if (!local) {
    out.write('(Already-running sessions need a restart to pick this up.)\n');
  }
  return failed ? 1 : 0;
}

/** Render the `claude mcp add ...` command as shell-quoted text for display/copy-paste. */
function claudeAddPreview(scope, launch) {
  const args = launchArgv(launch).map(shellQuote).join(' ');
  return `claude mcp add --scope ${scope} aikeychain -- ${args}`;
}

async function registerClaude(out, scope, launch) {
  try {
    await registerClaudeMcp(scope, launch);
    out.write(`  ✅ registered MCP server with Claude Code (aikeychain, ${scope} scope)\n`);
  } catch {
    out.write('  ⏭️  Claude Code CLI not found — register manually:\n');
    out.write(`       ${claudeAddPreview(scope, launch)}\n`);
  }
}
