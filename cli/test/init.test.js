import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdtemp, mkdir, readFile, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  upsertManagedBlock,
  upsertCodexBlock,
  renderManagedBlock,
  renderCodexBlock,
  resolveAkcLaunch,
  shellQuote,
  BLOCK_BEGIN,
  BLOCK_END,
  CODEX_BLOCK_BEGIN,
  CODEX_BLOCK_END,
  AGENT_INSTRUCTIONS,
} from '../src/agent-setup.js';
import { launchArgv, registrationMatches } from '../src/init.js';

const AKC = join(dirname(fileURLToPath(import.meta.url)), '..', 'bin', 'akc.js');
// The real, resolvable launch info for this checkout — used to assert that
// `akc init` registers with absolute paths, not the bare `akc` command
// (issue #131: bare `akc` is PATH-dependent and fails from GUI apps / cron /
// after a Node version switch).
const REAL_LAUNCH = resolveAkcLaunch();

test('AGENT_INSTRUCTIONS teaches the core rules', () => {
  assert.match(AGENT_INSTRUCTIONS, /keychain:\/\//);
  assert.match(AGENT_INSTRUCTIONS, /akc run/);
  assert.match(AGENT_INSTRUCTIONS, /usage_guide/);
});

test('AGENT_INSTRUCTIONS recommends `akc get` and presents both security lookup forms (#137)', () => {
  // Root cause of #137: the old guidance taught a single `-s ENV_VAR_NAME -w`
  // form. That form only works for [manual] keys; for AI KeyChain GUI ("app"
  // store) keys it returns exit 44, so agents falsely concluded the key was
  // unregistered. `akc get` handles both stores and must be the primary
  // recommendation; if raw `security` is shown, both forms must be present
  // and labeled, with a warning that exit 44 on the bare -s form is not proof
  // of "unregistered".
  assert.match(AGENT_INSTRUCTIONS, /akc get <KEY>/);
  assert.match(AGENT_INSTRUCTIONS, /-s "com\.aieo\.aikeychain" -a "<KEY>" -w/); // [app] store form
  assert.match(AGENT_INSTRUCTIONS, /-s "<KEY>" -w/); // [manual] form
  assert.match(AGENT_INSTRUCTIONS, /exit 44/);
  assert.match(AGENT_INSTRUCTIONS, /akc check <KEY>/);
  assert.match(AGENT_INSTRUCTIONS, /do NOT pin[\s\S]*-a "\$USER"/);
  // The bare single-service form must no longer be presented as the sole method.
  assert.doesNotMatch(AGENT_INSTRUCTIONS, /-s "ENV_VAR_NAME" -w/);
});

test('upsertManagedBlock creates a block in empty content', () => {
  const { content, action } = upsertManagedBlock('');
  assert.equal(action, 'created');
  assert.ok(content.includes(BLOCK_BEGIN));
  assert.ok(content.includes(BLOCK_END));
  assert.ok(content.endsWith('\n'));
});

test('upsertManagedBlock appends after existing content with separation', () => {
  const { content, action } = upsertManagedBlock('# My Project\n\nSome notes.\n');
  assert.equal(action, 'created');
  assert.ok(content.startsWith('# My Project\n\nSome notes.\n'));
  assert.ok(content.includes(BLOCK_BEGIN));
});

test('upsertManagedBlock is idempotent (re-run reports unchanged)', () => {
  const first = upsertManagedBlock('# Project\n');
  const second = upsertManagedBlock(first.content);
  assert.equal(second.action, 'unchanged');
  assert.equal(second.content, first.content);
  // exactly one block
  assert.equal(second.content.split(BLOCK_BEGIN).length - 1, 1);
});

test('upsertManagedBlock replaces an outdated block in place (no duplicate)', () => {
  const stale = `# Project\n\n${BLOCK_BEGIN}\nOLD CONTENT\n${BLOCK_END}\n\n## After\n`;
  const { content, action } = upsertManagedBlock(stale);
  assert.equal(action, 'updated');
  assert.equal(content.split(BLOCK_BEGIN).length - 1, 1); // still one block
  assert.ok(content.includes('## After')); // preserved trailing content
  assert.ok(!content.includes('OLD CONTENT'));
  assert.ok(content.includes(AGENT_INSTRUCTIONS));
});

test('upsertManagedBlock refuses to edit a dangling BEGIN (no END) — never truncates user content', () => {
  const broken = `# Project\n${BLOCK_BEGIN}\nhalf written\n\n## Important user notes kept\n`;
  const { content, action } = upsertManagedBlock(broken);
  assert.equal(action, 'malformed');
  assert.equal(content, broken); // untouched — user content preserved
  assert.ok(content.includes('## Important user notes kept'));
});

test('upsertManagedBlock refuses a dangling END (no BEGIN)', () => {
  const broken = `# Project\n${BLOCK_END}\nmore notes\n`;
  const { content, action } = upsertManagedBlock(broken);
  assert.equal(action, 'malformed');
  assert.equal(content, broken);
});

test('upsertManagedBlock canonicalizes duplicate blocks to exactly one, preserving surrounding text', () => {
  const dup = `# A\n\n${BLOCK_BEGIN}\nold1\n${BLOCK_END}\n\n## Middle\n\n${BLOCK_BEGIN}\nold2\n${BLOCK_END}\n\n## Tail\n`;
  const { content, action } = upsertManagedBlock(dup);
  assert.equal(action, 'updated');
  assert.equal(content.split(BLOCK_BEGIN).length - 1, 1); // exactly one block
  assert.ok(content.includes('## Middle'));
  assert.ok(content.includes('## Tail'));
  assert.ok(!content.includes('old1'));
  assert.ok(!content.includes('old2'));
  // re-running is now stable
  assert.equal(upsertManagedBlock(content).action, 'unchanged');
});

function runAkc(args, opts = {}) {
  return promisify(execFile)(process.execPath, [AKC, ...args], opts).then(
    (r) => ({ code: 0, ...r }),
    (e) => ({ code: e.code ?? 1, stdout: e.stdout ?? '', stderr: e.stderr ?? '' })
  );
}

test('upsertCodexBlock appends once and is idempotent when the launch is identical', () => {
  const existing = `[mcp_servers.node_repl]\ncommand = "node"\n`;
  const first = upsertCodexBlock(existing);
  assert.equal(first.action, 'created');
  assert.ok(first.content.startsWith(existing)); // existing config preserved
  assert.ok(first.content.includes(CODEX_BLOCK_BEGIN));
  assert.ok(first.content.includes('[mcp_servers.aikeychain]'));
  // re-run with the same launch re-renders in place → no change
  const second = upsertCodexBlock(first.content);
  assert.equal(second.action, 'unchanged');
  assert.equal(second.content, first.content);
});

test('upsertCodexBlock UPDATES a stale bare `akc` managed block to absolute paths (#131)', () => {
  // The exact issue-#131 population: a machine that already ran the OLD init,
  // so its config.toml holds a managed block with the bare `command = "akc"`.
  // Re-running init MUST refresh it — the old no-op behavior left it broken.
  const stale =
    `[mcp_servers.node_repl]\ncommand = "node"\n\n` +
    `${CODEX_BLOCK_BEGIN}\n[mcp_servers.aikeychain]\ncommand = "akc"\nargs = ["mcp"]\n${CODEX_BLOCK_END}\n`;
  const launch = { nodeBin: '/opt/homebrew/bin/node', akcJs: '/pkg/bin/akc.js' };
  const { content, action } = upsertCodexBlock(stale, launch);
  assert.equal(action, 'updated');
  assert.ok(content.includes('command = "/opt/homebrew/bin/node"'));
  assert.ok(content.includes('args = ["/pkg/bin/akc.js", "mcp"]'));
  assert.ok(!content.includes('command = "akc"'));
  assert.ok(content.includes('[mcp_servers.node_repl]')); // surrounding TOML preserved
  assert.equal(content.split(CODEX_BLOCK_BEGIN).length - 1, 1); // still exactly one block
  // stable on a second identical run
  assert.equal(upsertCodexBlock(content, launch).action, 'unchanged');
});

test('upsertCodexBlock UPDATES a stale absolute path (e.g. after a Node upgrade) to the new one (#131)', () => {
  const old = { nodeBin: '/nvm/v18/bin/node', akcJs: '/nvm/v18/pkg/bin/akc.js' };
  const seeded = upsertCodexBlock('', old).content;
  const fresh = { nodeBin: '/nvm/v22/bin/node', akcJs: '/nvm/v22/pkg/bin/akc.js' };
  const { content, action } = upsertCodexBlock(seeded, fresh);
  assert.equal(action, 'updated');
  assert.ok(content.includes('/nvm/v22/bin/node'));
  assert.ok(!content.includes('/nvm/v18/'));
});

test('upsertCodexBlock refuses to edit a dangling BEGIN marker (never truncates user TOML)', () => {
  const broken = `[keep.me]\nx = 1\n\n${CODEX_BLOCK_BEGIN}\n[mcp_servers.aikeychain]\ncommand = "akc"\n`;
  const { content, action } = upsertCodexBlock(broken, { nodeBin: '/n', akcJs: '/a' });
  assert.equal(action, 'malformed');
  assert.equal(content, broken);
});

test('upsertCodexBlock refuses to append when a marker-less aikeychain table already exists', () => {
  // The exact hazard: user hand-wrote the table without our markers.
  const existing = `[mcp_servers.node_repl]\ncommand = "node"\n\n[mcp_servers.aikeychain]\ncommand = "akc"\nargs = ["mcp"]\n`;
  const { content, action } = upsertCodexBlock(existing);
  assert.equal(action, 'conflict');
  assert.equal(content, existing); // untouched — never produces duplicate table
  // and it must NOT have appended a second table
  assert.equal((content.match(/\[mcp_servers\.aikeychain\]/g) || []).length, 1);
});

// --- issue #131: PATH-independent (absolute path) MCP registration ---

test('resolveAkcLaunch resolves this checkout\'s own node binary + bin/akc.js', () => {
  assert.ok(REAL_LAUNCH, 'resolveAkcLaunch should succeed inside this checkout');
  assert.equal(REAL_LAUNCH.nodeBin, process.execPath);
  assert.equal(REAL_LAUNCH.akcJs, AKC);
  assert.ok(REAL_LAUNCH.akcJs.endsWith(join('bin', 'akc.js')));
});

test('renderCodexBlock uses absolute paths (process.execPath + bin/akc.js) when given launch info', () => {
  const launch = { nodeBin: '/opt/homebrew/bin/node', akcJs: '/Users/me/aikeychain/bin/akc.js' };
  const block = renderCodexBlock(launch);
  assert.ok(block.includes('command = "/opt/homebrew/bin/node"'));
  assert.ok(block.includes('args = ["/Users/me/aikeychain/bin/akc.js", "mcp"]'));
  assert.ok(!block.includes('command = "akc"'));
  assert.match(block, /re-run `akc init`/i);
});

test('renderCodexBlock falls back to bare "akc" when no launch info is given', () => {
  const block = renderCodexBlock();
  assert.ok(block.includes('command = "akc"'));
  assert.ok(block.includes('args = ["mcp"]'));
});

test('renderCodexBlock TOML-escapes paths containing quotes/backslashes', () => {
  const launch = { nodeBin: 'C:\\weird"node.exe', akcJs: '/tmp/akc.js' };
  const block = renderCodexBlock(launch);
  assert.ok(block.includes('command = "C:\\\\weird\\"node.exe"'));
});

test('upsertCodexBlock threads launch info through to the rendered block', () => {
  const launch = { nodeBin: '/abs/node', akcJs: '/abs/bin/akc.js' };
  const { content, action } = upsertCodexBlock('', launch);
  assert.equal(action, 'created');
  assert.ok(content.includes('command = "/abs/node"'));
  assert.ok(content.includes('args = ["/abs/bin/akc.js", "mcp"]'));
});

test('shellQuote leaves plain paths bare and single-quotes paths with spaces/specials', () => {
  assert.equal(shellQuote('/usr/local/bin/node'), '/usr/local/bin/node');
  assert.equal(shellQuote('/Users/a b/akc.js'), "'/Users/a b/akc.js'");
  assert.equal(shellQuote("/it's/here"), "'/it'\\''s/here'");
});

test('renderCodexBlock escapes control characters (newline/tab) in a TOML basic string', () => {
  const launch = { nodeBin: '/n\tode\npath', akcJs: '/tmp/akc.js' };
  const block = renderCodexBlock(launch);
  assert.ok(block.includes('command = "/n\\tode\\npath"'));
  // no raw control char leaked into the TOML
  assert.ok(!/command = "[^"]*\t/.test(block));
});

test('launchArgv uses absolute node + akc.js when launch resolves, bare `akc` otherwise', () => {
  assert.deepEqual(launchArgv({ nodeBin: '/n', akcJs: '/a/akc.js' }), ['/n', '/a/akc.js', 'mcp']);
  assert.deepEqual(launchArgv(null), ['akc', 'mcp']);
});

test('registrationMatches: a `claude mcp get` output matches only when every launch token is present', () => {
  const absolute = ['/opt/homebrew/bin/node', '/pkg/bin/akc.js', 'mcp'];
  // A matching absolute registration → keep it (no replace).
  const good = 'aikeychain:\n  Command: /opt/homebrew/bin/node\n  Args: /pkg/bin/akc.js mcp\n';
  assert.equal(registrationMatches(good, absolute), true);
  // The OLD bare registration → mismatch → must be replaced.
  const bare = 'aikeychain:\n  Command: akc\n  Args: mcp\n';
  assert.equal(registrationMatches(bare, absolute), false);
  // A STALE absolute path from an old Node version dir → mismatch → replace.
  const stale = 'aikeychain:\n  Command: /nvm/v18/bin/node\n  Args: /nvm/v18/pkg/bin/akc.js mcp\n';
  assert.equal(registrationMatches(stale, absolute), false);
});

test('akc init --print previews machine-wide setup without writing, using absolute paths (#131)', async () => {
  const r = await runAkc(['init', '--print']);
  assert.equal(r.code, 0);
  assert.match(r.stdout, new RegExp(BLOCK_BEGIN.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
  assert.match(r.stdout, /\[mcp_servers\.aikeychain\]/);
  // Not the old PATH-dependent bare command:
  assert.doesNotMatch(r.stdout, /claude mcp add --scope user aikeychain -- akc mcp/);
  // Absolute paths for both the Claude add command and the Codex TOML block:
  assert.ok(REAL_LAUNCH, 'this checkout should resolve a real launch');
  const claudeLine = r.stdout.split('\n').find((l) => l.includes('claude mcp add'));
  assert.ok(claudeLine, 'expected a `claude mcp add` preview line');
  assert.ok(claudeLine.includes(REAL_LAUNCH.nodeBin));
  assert.ok(claudeLine.includes(REAL_LAUNCH.akcJs));
  assert.match(claudeLine, /\bmcp$/);
  assert.ok(r.stdout.includes(`command = "${REAL_LAUNCH.nodeBin}"`));
  assert.ok(r.stdout.includes(`args = ["${REAL_LAUNCH.akcJs}", "mcp"]`));
  // End-to-end: the rendered template shows BOTH security lookup forms
  // (store + manual) and recommends `akc get`, so the #137 correction is
  // guaranteed at the CLI-output level, not just in the AGENT_INSTRUCTIONS
  // constant.
  assert.match(r.stdout, /-s "com\.aieo\.aikeychain" -a "<KEY>" -w/); // [app] store form
  assert.match(r.stdout, /-s "<KEY>" -w/); // [manual] form
  assert.match(r.stdout, /akc get <KEY>/);
  assert.doesNotMatch(r.stdout, /-s "ENV_VAR_NAME" -w/); // old sole-method form is gone
});

test('akc init (default machine-wide) writes ~/.claude + ~/.codex under HOME, idempotently', async () => {
  const home = await mkdtemp(join(tmpdir(), 'akc-home-'));
  const env = { ...process.env, HOME: home };
  const first = await runAkc(['init', '--no-register'], { env });
  assert.equal(first.code, 0);

  const claudeMd = await readFile(join(home, '.claude', 'CLAUDE.md'), 'utf8');
  const codexAgents = await readFile(join(home, '.codex', 'AGENTS.md'), 'utf8');
  const codexToml = await readFile(join(home, '.codex', 'config.toml'), 'utf8');
  assert.ok(claudeMd.includes(BLOCK_BEGIN));
  assert.ok(codexAgents.includes(BLOCK_BEGIN));
  assert.ok(codexToml.includes('[mcp_servers.aikeychain]'));
  // Registered with an absolute path, not the bare, PATH-dependent `akc` (#131).
  assert.ok(REAL_LAUNCH, 'this checkout should resolve a real launch');
  assert.ok(codexToml.includes(`command = "${REAL_LAUNCH.nodeBin}"`));
  assert.ok(codexToml.includes(`args = ["${REAL_LAUNCH.akcJs}", "mcp"]`));
  assert.ok(!codexToml.includes('command = "akc"'));

  // Re-run is idempotent: still exactly one block in each.
  await runAkc(['init', '--no-register'], { env });
  const claudeMd2 = await readFile(join(home, '.claude', 'CLAUDE.md'), 'utf8');
  const codexToml2 = await readFile(join(home, '.codex', 'config.toml'), 'utf8');
  assert.equal(claudeMd2.split(BLOCK_BEGIN).length - 1, 1);
  assert.equal(codexToml2.split(CODEX_BLOCK_BEGIN).length - 1, 1);
});

test('akc init upgrades an OLD bare-`akc` Codex block to absolute paths on re-run (#131)', async () => {
  const home = await mkdtemp(join(tmpdir(), 'akc-home-'));
  const env = { ...process.env, HOME: home };
  // Simulate a machine that ran the OLD init: a managed Codex block with the
  // bare, PATH-dependent `command = "akc"`.
  const codexDir = join(home, '.codex');
  await mkdir(codexDir, { recursive: true });
  const staleBlock =
    `${CODEX_BLOCK_BEGIN}\n[mcp_servers.aikeychain]\ncommand = "akc"\nargs = ["mcp"]\n${CODEX_BLOCK_END}\n`;
  await writeFile(join(codexDir, 'config.toml'), `[mcp_servers.keep]\ncommand = "x"\n\n${staleBlock}`);

  const r = await runAkc(['init', '--no-register'], { env });
  assert.equal(r.code, 0);
  const codexToml = await readFile(join(codexDir, 'config.toml'), 'utf8');
  assert.ok(REAL_LAUNCH, 'this checkout should resolve a real launch');
  // The stale bare command is gone, replaced by the absolute paths.
  assert.ok(!codexToml.includes('command = "akc"'));
  assert.ok(codexToml.includes(`command = "${REAL_LAUNCH.nodeBin}"`));
  assert.ok(codexToml.includes(`args = ["${REAL_LAUNCH.akcJs}", "mcp"]`));
  assert.ok(codexToml.includes('[mcp_servers.keep]')); // unrelated table preserved
  assert.equal(codexToml.split(CODEX_BLOCK_BEGIN).length - 1, 1); // still one block
});

test('akc init --local writes cwd CLAUDE.md + AGENTS.md, preserving existing content', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'akc-init-'));
  const first = await runAkc(['init', '--local', '--no-register'], { cwd: dir });
  assert.equal(first.code, 0);
  assert.ok((await readFile(join(dir, 'CLAUDE.md'), 'utf8')).includes(BLOCK_BEGIN));
  assert.ok((await readFile(join(dir, 'AGENTS.md'), 'utf8')).includes(BLOCK_BEGIN));

  // Pre-existing content is preserved, block appended once, then stable.
  await writeFile(join(dir, 'CLAUDE.md'), `# Existing\n\nrules here\n`);
  await runAkc(['init', '--local', '--no-register'], { cwd: dir });
  const updated = await readFile(join(dir, 'CLAUDE.md'), 'utf8');
  assert.ok(updated.startsWith('# Existing'));
  assert.equal(updated.split(BLOCK_BEGIN).length - 1, 1);
  await runAkc(['init', '--local', '--no-register'], { cwd: dir });
  assert.equal(await readFile(join(dir, 'CLAUDE.md'), 'utf8'), updated);
});
