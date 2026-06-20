import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  upsertManagedBlock,
  upsertCodexBlock,
  renderManagedBlock,
  BLOCK_BEGIN,
  BLOCK_END,
  CODEX_BLOCK_BEGIN,
  AGENT_INSTRUCTIONS,
} from '../src/agent-setup.js';

const AKC = join(dirname(fileURLToPath(import.meta.url)), '..', 'bin', 'akc.js');

test('AGENT_INSTRUCTIONS teaches the core rules', () => {
  assert.match(AGENT_INSTRUCTIONS, /keychain:\/\//);
  assert.match(AGENT_INSTRUCTIONS, /akc run/);
  assert.match(AGENT_INSTRUCTIONS, /-s "ENV_VAR_NAME" -w/);
  assert.match(AGENT_INSTRUCTIONS, /do NOT pin `-a "\$USER"`/);
  assert.match(AGENT_INSTRUCTIONS, /usage_guide/);
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

test('upsertCodexBlock appends once and is idempotent (never reformats existing TOML)', () => {
  const existing = `[mcp_servers.node_repl]\ncommand = "node"\n`;
  const first = upsertCodexBlock(existing);
  assert.equal(first.action, 'created');
  assert.ok(first.content.startsWith(existing)); // existing config untouched
  assert.ok(first.content.includes(CODEX_BLOCK_BEGIN));
  assert.ok(first.content.includes('[mcp_servers.aikeychain]'));
  // re-run leaves it completely unchanged
  const second = upsertCodexBlock(first.content);
  assert.equal(second.action, 'unchanged');
  assert.equal(second.content, first.content);
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

test('akc init --print previews machine-wide setup without writing', async () => {
  const r = await runAkc(['init', '--print']);
  assert.equal(r.code, 0);
  assert.match(r.stdout, new RegExp(BLOCK_BEGIN.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
  assert.match(r.stdout, /claude mcp add --scope user aikeychain -- akc mcp/);
  assert.match(r.stdout, /\[mcp_servers\.aikeychain\]/);
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

  // Re-run is idempotent: still exactly one block in each.
  await runAkc(['init', '--no-register'], { env });
  const claudeMd2 = await readFile(join(home, '.claude', 'CLAUDE.md'), 'utf8');
  const codexToml2 = await readFile(join(home, '.codex', 'config.toml'), 'utf8');
  assert.equal(claudeMd2.split(BLOCK_BEGIN).length - 1, 1);
  assert.equal(codexToml2.split(CODEX_BLOCK_BEGIN).length - 1, 1);
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
