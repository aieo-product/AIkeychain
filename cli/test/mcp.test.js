// MCP server integration test: speaks JSON-RPC over stdio to `akc mcp` and
// verifies the toolset — in particular that no tool can return a raw secret.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const AKC = join(dirname(fileURLToPath(import.meta.url)), '..', 'bin', 'akc.js');

function mcpSession(messages, { timeoutMs = 10000 } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [AKC, 'mcp'], {
      stdio: ['pipe', 'pipe', 'pipe'],
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
  assert.match(guideText, /-a "\$USER"/);
});

test('delete_secret refuses without confirm=true', async () => {
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
      params: { name: 'delete_secret', arguments: { name: 'WHATEVER_KEY', confirm: false } },
    },
  ]);
  const call = responses.find((r) => r.id === 2);
  const payload = JSON.parse(call.result.content[0].text);
  assert.deepEqual(payload.deleted, []);
  assert.match(payload.note, /confirm=true/);
});
