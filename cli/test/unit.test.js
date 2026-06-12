import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  parseDump,
  maskValue,
  findAmbiguousDuplicates,
  MANUAL_NAME_PATTERN,
  GUI_SERVICE,
} from '../src/keychain.js';
import { collectRefs } from '../src/run.js';
import { scanShellConfig } from '../src/doctor.js';

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

test('maskValue never includes the value', () => {
  assert.equal(maskValue('super-secret'), '****** (12 chars)');
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
