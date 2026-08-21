import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseDump, maskValue, MANAGED_SERVICE } from '../src/keychain.js';
import { collectRefs } from '../src/run.js';
import {
  scanShellConfig,
  extractCodexAikeychainCommand,
  classifyMcpCommand,
} from '../src/doctor.js';

const SAMPLE_DUMP = `keychain: "/Users/x/Library/Keychains/login.keychain-db"
version: 512
class: "genp"
attributes:
    "acct"<blob>="GITHUB_TOKEN"
    "svce"<blob>="com.aieo.aikeychain.managed"
keychain: "/Users/x/Library/Keychains/login.keychain-db"
version: 512
class: "inet"
attributes:
    "acct"<blob>="ignored"
    "srvr"<blob>="example.com"
keychain: "/Users/x/Library/Keychains/login.keychain-db"
version: 512
class: "genp"
attributes:
    "acct"<blob>="user@example.com"
    "svce"<blob>="com.apple.something"
`;

test('parseDump extracts genp service/account pairs only', () => {
  const records = parseDump(SAMPLE_DUMP);
  assert.equal(records.length, 2); // inet record excluded
  assert.deepEqual(records[0], { service: MANAGED_SERVICE, account: 'GITHUB_TOKEN' });
  assert.deepEqual(records[1], { service: 'com.apple.something', account: 'user@example.com' });
});

test('maskValue never includes the value nor its length', () => {
  // 固定長マスク: 値そのものも、正確な桁数も漏らさない (#115/#123 と統一)
  assert.equal(maskValue('super-secret'), '********');
  assert.equal(maskValue('a'), '********');
  assert.equal(maskValue('a-much-longer-secret-value-0123456789'), '********');
  // 桁数が出力に含まれないこと
  assert.doesNotMatch(maskValue('super-secret'), /\d/);
  assert.doesNotMatch(maskValue('super-secret'), /chars/);
});

test('collectRefs picks only keychain:// values', () => {
  const refs = collectRefs({
    GITHUB_TOKEN: 'keychain://GITHUB_TOKEN',
    RENAMED: 'keychain://OTHER_KEY',
    PLAIN: 'not-a-ref',
    EMPTY: '',
  });
  assert.deepEqual(refs, [
    { varName: 'GITHUB_TOKEN', keyName: 'GITHUB_TOKEN' },
    { varName: 'RENAMED', keyName: 'OTHER_KEY' },
  ]);
});

test('scanShellConfig finds keychain:// refs and managed export lines (v2.0 #188)', () => {
  const { keys } = scanShellConfig(`
export GITHUB_TOKEN=keychain://GITHUB_TOKEN
export ANTHROPIC_API_KEY=$(security find-generic-password -s "com.aieo.aikeychain.managed" -a "ANTHROPIC_API_KEY" -w)
# export COMMENTED=$(security find-generic-password -s "com.aieo.aikeychain.managed" -a "COMMENTED" -w)
`);
  // managed export line: real key name is on -a, not the shared service name.
  assert.deepEqual(keys, ['ANTHROPIC_API_KEY', 'GITHUB_TOKEN']);
  assert.ok(!keys.includes('com.aieo.aikeychain.managed'));
});

test('scanShellConfig ignores non-managed security lookups (#187: managed only)', () => {
  // v2.0: legacy GUI store / manual scheme lines are not scanned. Crucially the
  // managed service name must NOT be registered as a key (the #187 misparse).
  const { keys } = scanShellConfig(`
export A=$(security find-generic-password -s "com.aieo.aikeychain.managed" -a "A" -w)
export B=$(security find-generic-password -s "com.aieo.aikeychain" -a "B" -w)
export C=$(security find-generic-password -s "C" -w)
`);
  assert.deepEqual(keys, ['A']);
  assert.ok(!keys.includes('com.aieo.aikeychain.managed'));
});

// --- issue #131: doctor MCP registration path-independence checks (hermetic) ---

test('extractCodexAikeychainCommand reads command only from the [mcp_servers.aikeychain] table', () => {
  const toml = `[mcp_servers.other]
command = "akc"
args = ["x"]

# BEGIN aikeychain (managed by \`akc init\`)
[mcp_servers.aikeychain]
command = "/opt/homebrew/bin/node"
args = ["/pkg/bin/akc.js", "mcp"]
# END aikeychain (managed by \`akc init\`)
`;
  // Must NOT be fooled by the other server's bare command = "akc".
  assert.equal(extractCodexAikeychainCommand(toml), '/opt/homebrew/bin/node');
});

test('extractCodexAikeychainCommand returns null when there is no aikeychain table', () => {
  assert.equal(extractCodexAikeychainCommand(`[mcp_servers.other]\ncommand = "akc"\n`), null);
});

test('extractCodexAikeychainCommand unescapes a TOML basic string', () => {
  const toml = `[mcp_servers.aikeychain]\ncommand = "/a b/n\\"ode"\n`;
  assert.equal(extractCodexAikeychainCommand(toml), '/a b/n"ode');
});

test('classifyMcpCommand flags bare `akc` (PATH-dependent)', () => {
  const r = classifyMcpCommand('akc', { exists: () => true });
  assert.equal(r.ok, false);
  assert.equal(r.kind, 'bare');
});

test('classifyMcpCommand flags a non-absolute command (still PATH-dependent)', () => {
  const r = classifyMcpCommand('node', { exists: () => true });
  assert.equal(r.ok, false);
  assert.equal(r.kind, 'bare');
});

test('classifyMcpCommand flags an absolute path that no longer exists as stale', () => {
  const r = classifyMcpCommand('/nvm/v18/bin/node', { exists: () => false });
  assert.equal(r.ok, false);
  assert.equal(r.kind, 'stale');
  assert.equal(r.command, '/nvm/v18/bin/node');
});

test('classifyMcpCommand passes an absolute path that exists (PATH-independent)', () => {
  const r = classifyMcpCommand('/opt/homebrew/bin/node', { exists: () => true });
  assert.equal(r.ok, true);
  assert.equal(r.kind, 'absolute');
});

test('classifyMcpCommand returns null when there is nothing to check', () => {
  assert.equal(classifyMcpCommand(undefined), null);
  assert.equal(classifyMcpCommand(''), null);
});
