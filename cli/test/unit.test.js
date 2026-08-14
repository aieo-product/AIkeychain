import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  parseDump,
  maskValue,
  findAmbiguousDuplicates,
  findUnmigratedKeys,
  MANUAL_NAME_PATTERN,
  GUI_SERVICE,
} from '../src/keychain.js';
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
    0x00000007 <blob>="com.aieo.aikeychain"
    "acct"<blob>="GITHUB_TOKEN"
    "svce"<blob>="com.aieo.aikeychain"
keychain: "/Users/x/Library/Keychains/login.keychain-db"
version: 512
class: "genp"
attributes:
    "acct"<blob>="takehiro"
    "svce"<blob>="QIITA_TOKEN"
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
  assert.equal(records.length, 3); // inet record excluded
  assert.deepEqual(records[0], { service: GUI_SERVICE, account: 'GITHUB_TOKEN' });
  assert.deepEqual(records[1], { service: 'QIITA_TOKEN', account: 'takehiro' });
});

test('MANUAL_NAME_PATTERN accepts env-var names and rejects bundle ids', () => {
  assert.ok(MANUAL_NAME_PATTERN.test('GITHUB_TOKEN'));
  assert.ok(MANUAL_NAME_PATTERN.test('X_POCOLOCO_CONSUMER_KEY'));
  assert.ok(!MANUAL_NAME_PATTERN.test('com.apple.something'));
  assert.ok(!MANUAL_NAME_PATTERN.test('lowercase_token'));
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

test('findUnmigratedKeys reports legacy-only keys and skips migrated ones (#171)', () => {
  const records = [
    // managed 済み → 対象外（GUI store に古いコピーが残っていても）
    { service: 'com.aieo.aikeychain.managed', account: 'MIGRATED_KEY' },
    { service: 'com.aieo.aikeychain', account: 'MIGRATED_KEY' },
    // GUI store のみ → 未移行
    { service: 'com.aieo.aikeychain', account: 'GUI_ONLY_KEY' },
    // manual スキームのみ → 未移行
    { service: 'MANUAL_ONLY_KEY', account: 'takehiro' },
    // 両レガシーに存在 → 1 件にまとめて両 store を列挙
    { service: 'com.aieo.aikeychain', account: 'BOTH_LEGACY_KEY' },
    { service: 'BOTH_LEGACY_KEY', account: null },
    // env 変数形でない service は manual と見なさない（他アプリのアイテム）
    { service: 'com.vendor.other', account: 'x' },
    { service: 'lowercase_svc', account: 'x' },
  ];
  const { keys, unparseable } = findUnmigratedKeys(records);
  assert.deepEqual(keys, [
    { name: 'BOTH_LEGACY_KEY', stores: ['gui', 'manual'] },
    { name: 'GUI_ONLY_KEY', stores: ['gui'] },
    { name: 'MANUAL_ONLY_KEY', stores: ['manual'] },
  ]);
  assert.equal(unparseable, 0);
});

test('findUnmigratedKeys returns empty when everything is migrated', () => {
  const records = [
    { service: 'com.aieo.aikeychain.managed', account: 'A_KEY' },
    { service: 'com.aieo.aikeychain.managed', account: 'B_KEY' },
  ];
  assert.deepEqual(findUnmigratedKeys(records), { keys: [], unparseable: 0 });
});

test('findUnmigratedKeys never reports the app-reserved service names (#185 S10)', () => {
  // KeyShareService の予約 service（共有秘密鍵/署名鍵）はドット+小文字を含み、
  // MANUAL_NAME_PATTERN（大文字スネーク限定）が除外する。パターンが緩む回帰が
  // 入ると「akc set com.aieo.aikeychain.sharekey しろ」と誤案内する事故になる。
  const records = [
    { service: 'com.aieo.aikeychain.sharekey', account: 'private_key' },
    { service: 'com.aieo.aikeychain.signkey', account: 'signing_key' },
  ];
  assert.deepEqual(findUnmigratedKeys(records), { keys: [], unparseable: 0 });
});

test('findUnmigratedKeys counts unparseable store records instead of dropping them (#185 S8)', () => {
  // GUI/managed store のレコードで acct が解析できない場合、そのキーが未移行か
  // どうか判定できない。黙って捨てると「未移行なし」の false negative になる。
  const records = [
    { service: 'com.aieo.aikeychain', account: null },
    { service: 'com.aieo.aikeychain.managed', account: null },
    { service: 'com.aieo.aikeychain', account: 'GUI_ONLY_KEY' },
  ];
  const { keys, unparseable } = findUnmigratedKeys(records);
  assert.equal(unparseable, 2);
  assert.deepEqual(keys, [{ name: 'GUI_ONLY_KEY', stores: ['gui'] }]);
});

test('findAmbiguousDuplicates flags same-service multi-acct entries (issue #91)', () => {
  // The exact #91 scenario: CLOUDFLARE_API_TOKEN exists twice with different accts.
  const records = [
    { service: 'CLOUDFLARE_API_TOKEN', account: 'takehiro' },
    { service: 'CLOUDFLARE_API_TOKEN', account: 'CLOUDFLARE_API_TOKEN' },
    { service: 'GITHUB_TOKEN', account: 'GITHUB_TOKEN' }, // single → fine
    { service: GUI_SERVICE, account: 'ANTHROPIC_API_KEY' }, // GUI store → ignored
    { service: GUI_SERVICE, account: 'OPENAI_API_KEY' },
    { service: 'com.apple.foo', account: 'a' }, // non-env-var service → ignored
    { service: 'com.apple.foo', account: 'b' },
  ];
  const dups = findAmbiguousDuplicates(records);
  assert.equal(dups.length, 1);
  assert.equal(dups[0].service, 'CLOUDFLARE_API_TOKEN');
  assert.deepEqual(dups[0].accounts, ['CLOUDFLARE_API_TOKEN', 'takehiro']);
});

test('findAmbiguousDuplicates returns empty when every service is unique', () => {
  const records = [
    { service: 'GITHUB_TOKEN', account: 'GITHUB_TOKEN' },
    { service: 'QIITA_TOKEN', account: 'takehiro' },
    { service: GUI_SERVICE, account: 'GITHUB_TOKEN' }, // app+manual for same key is not a same-service dup
  ];
  assert.deepEqual(findAmbiguousDuplicates(records), []);
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

test('scanShellConfig finds refs, security lookups, and the -a $USER pitfall', () => {
  const { keys, warnings } = scanShellConfig(`
export GITHUB_TOKEN=keychain://GITHUB_TOKEN
export QIITA_TOKEN=$(security find-generic-password -s "QIITA_TOKEN" -w)
export BAD_TOKEN=$(security find-generic-password -s "BAD_TOKEN" -a "$USER" -w)
# export COMMENTED=$(security find-generic-password -s "COMMENTED" -w)
`);
  assert.deepEqual(keys, ['BAD_TOKEN', 'GITHUB_TOKEN', 'QIITA_TOKEN']);
  assert.equal(warnings.length, 1);
  assert.match(warnings[0], /BAD_TOKEN/);
});

test('scanShellConfig extracts the key from -a for GUI-pinned lines', () => {
  // AI KeyChain GUI が生成する新形式: -s は共通サービス名なので、実キー名は -a 側。
  const { keys, warnings } = scanShellConfig(`
export ANTHROPIC_API_KEY=$(security find-generic-password -s "com.aieo.aikeychain" -a "ANTHROPIC_API_KEY" -w)
export OPENAI_API_KEY=$(security find-generic-password -s "com.aieo.aikeychain" -a "OPENAI_API_KEY" -w)
`);
  // 共通サービス名 "com.aieo.aikeychain" ではなく、各キー名が採取される
  assert.deepEqual(keys, ['ANTHROPIC_API_KEY', 'OPENAI_API_KEY']);
  assert.ok(!keys.includes('com.aieo.aikeychain'));
  // 新形式は -a "$USER" を使わないので警告なし
  assert.equal(warnings.length, 0);
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
