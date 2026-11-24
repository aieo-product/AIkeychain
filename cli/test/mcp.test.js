// MCP server integration test: speaks JSON-RPC over stdio to `akc mcp` and
// verifies the toolset — in particular that no tool can return a raw secret.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { chmod, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const AKC = join(dirname(fileURLToPath(import.meta.url)), '..', 'bin', 'akc.js');

function mcpSession(messages, { timeoutMs = 10000, env } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [AKC, 'mcp'], {
      stdio: ['pipe', 'pipe', 'pipe'],
      ...(env ? { env: { ...process.env, ...env } } : {}),
    });
    const responses = [];
    let buffer = '';
    const timer = setTimeout(() => {
      child.kill();
      reject(new Error(`timed out; got ${responses.length} responses`));
    }, timeoutMs);

    child.stdout.on('data', (chunk) => {
      buffer += chunk;
      let nl;
      while ((nl = buffer.indexOf('\n')) >= 0) {
        const line = buffer.slice(0, nl);
        buffer = buffer.slice(nl + 1);
        if (!line.trim()) continue;
        responses.push(JSON.parse(line));
        const expected = messages.filter((m) => m.id !== undefined).length;
        if (responses.length >= expected) {
          clearTimeout(timer);
          child.kill();
          resolve(responses);
          return;
        }
      }
    });
    child.on('error', (err) => {
      clearTimeout(timer);
      reject(err);
    });
    for (const message of messages) {
      child.stdin.write(`${JSON.stringify(message)}\n`);
    }
  });
}

test('mcp server lists the expected tools and none returns raw values', async () => {
  const responses = await mcpSession([
    {
      jsonrpc: '2.0',
      id: 1,
      method: 'initialize',
      params: {
        protocolVersion: '2025-06-18',
        capabilities: {},
        clientInfo: { name: 'akc-test', version: '0.0.0' },
      },
    },
    { jsonrpc: '2.0', method: 'notifications/initialized' },
    { jsonrpc: '2.0', id: 2, method: 'tools/list' },
  ]);

  const init = responses.find((r) => r.id === 1);
  assert.equal(init.result.serverInfo.name, 'aikeychain');

  const toolsResult = responses.find((r) => r.id === 2);
  const names = toolsResult.result.tools.map((t) => t.name).sort();
  assert.deepEqual(names, [
    'check_key',
    'delete_secret',
    'doctor',
    'get_secret_reference',
    'list_keys',
    'set_secret',
    'usage_guide',
  ]);
  // No tool name suggests raw value retrieval.
  assert.ok(!names.some((n) => /get_secret$|get_value|reveal/.test(n)));
});

test('usage_guide returns the agent guide text', async () => {
  const responses = await mcpSession([
    {
      jsonrpc: '2.0',
      id: 1,
      method: 'initialize',
      params: {
        protocolVersion: '2025-06-18',
        capabilities: {},
        clientInfo: { name: 'akc-test', version: '0.0.0' },
      },
    },
    { jsonrpc: '2.0', method: 'notifications/initialized' },
    {
      jsonrpc: '2.0',
      id: 2,
      method: 'tools/call',
      params: { name: 'usage_guide', arguments: {} },
    },
  ]);
  const call = responses.find((r) => r.id === 2);
  const guideText = call.result.content[0].text;
  assert.match(guideText, /keychain:\/\//);
  assert.match(guideText, /akc run/);
  // v2 (#188): the guide points at the managed namespace form; the legacy
  // `-a "$USER"` pin (#91) must not be suggested anymore.
  assert.match(guideText, /-s "com\.aieo\.aikeychain\.managed" -a "<KEY>"/);
  assert.doesNotMatch(guideText, /-a "\$USER"/);
});

test('delete_secret refuses without confirm=true', async () => {
  // Record every `security` call through a stub so the test can prove that no
  // delete ran (and never touches the real Keychain). The stub says the key exists.
  const stubDir = await mkdtemp(join(tmpdir(), 'akc-mcp-delete-'));
  const callsPath = join(stubDir, 'calls');
  const stubPath = join(stubDir, 'security');
  await writeFile(callsPath, '');
  await writeFile(stubPath, `#!/bin/bash\nprintf '%s\\n' "$1" >> "${callsPath}"\nexit 0\n`);
  await chmod(stubPath, 0o755);
  let responses;
  let calls = '';
  try {
    responses = await mcpSession(
      [
        {
          jsonrpc: '2.0',
          id: 1,
          method: 'initialize',
          params: {
            protocolVersion: '2025-06-18',
            capabilities: {},
            clientInfo: { name: 'akc-test', version: '0.0.0' },
          },
        },
        { jsonrpc: '2.0', method: 'notifications/initialized' },
        {
          jsonrpc: '2.0',
          id: 2,
          method: 'tools/call',
          params: { name: 'delete_secret', arguments: { name: 'WHATEVER_KEY', confirm: false } },
        },
      ],
      { env: { AIKEYCHAIN_SECURITY_BIN: stubPath } }
    );
  } finally {
    calls = await readFile(callsPath, 'utf8').catch(() => '');
    await rm(stubDir, { recursive: true, force: true });
  }
  assert.doesNotMatch(calls, /delete-generic-password/, 'confirm=false must not run any delete');
  const call = responses.find((r) => r.id === 2);
  const payload = JSON.parse(call.result.content[0].text);
  // v2: `deleted` is a boolean (was an array of removed entries in v1)
  assert.equal(payload.deleted, false);
  assert.match(payload.note, /confirm=true/);
});
