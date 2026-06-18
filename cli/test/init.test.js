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
  renderManagedBlock,
  BLOCK_BEGIN,
  BLOCK_END,
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

test('upsertManagedBlock handles a dangling begin marker (no end)', () => {
  const broken = `# Project\n${BLOCK_BEGIN}\nhalf written`;
  const { content, action } = upsertManagedBlock(broken);
  assert.equal(action, 'updated');
  assert.ok(content.includes(BLOCK_END));
  assert.equal(content.split(BLOCK_BEGIN).length - 1, 1);
});

function runAkc(args, opts = {}) {
  return promisify(execFile)(process.execPath, [AKC, ...args], opts).then(
    (r) => ({ code: 0, ...r }),
    (e) => ({ code: e.code ?? 1, stdout: e.stdout ?? '', stderr: e.stderr ?? '' })
  );
}

test('akc init --print previews without writing files', async () => {
  const r = await runAkc(['init', '--print']);
  assert.equal(r.code, 0);
  assert.match(r.stdout, new RegExp(BLOCK_BEGIN.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
  assert.match(r.stdout, /claude mcp add aikeychain -- akc mcp/);
  assert.match(r.stdout, /\[mcp_servers\.aikeychain\]/);
});

test('akc init writes CLAUDE.md + AGENTS.md and is idempotent', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'akc-init-'));
  // --no-register so the test never touches the real Claude config.
  const first = await runAkc(['init', '--no-register'], { cwd: dir });
  assert.equal(first.code, 0);
  const claudeMd = await readFile(join(dir, 'CLAUDE.md'), 'utf8');
  const agentsMd = await readFile(join(dir, 'AGENTS.md'), 'utf8');
  assert.ok(claudeMd.includes(BLOCK_BEGIN));
  assert.ok(agentsMd.includes(BLOCK_BEGIN));
  assert.match(first.stdout, /skipped MCP registration/);

  // Pre-existing content is preserved, block appended once.
  await writeFile(join(dir, 'CLAUDE.md'), `# Existing\n\nrules here\n`);
  await runAkc(['init', '--no-register'], { cwd: dir });
  const updated = await readFile(join(dir, 'CLAUDE.md'), 'utf8');
  assert.ok(updated.startsWith('# Existing'));
  assert.equal(updated.split(BLOCK_BEGIN).length - 1, 1);

  // Third run: unchanged, still exactly one block.
  await runAkc(['init', '--no-register'], { cwd: dir });
  const third = await readFile(join(dir, 'CLAUDE.md'), 'utf8');
  assert.equal(third.split(BLOCK_BEGIN).length - 1, 1);
  assert.equal(third, updated);
});
