import { after, before, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { chmod, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

let resolveKey;
let keyExists;
let resolveRefs;
let stubDir;
let callsPath;

// v2.0 (#188): the managed namespace is the ONLY store. The stub answers only
// for service="com.aieo.aikeychain.managed"; every other service exits 44.
const STUB = `#!/bin/bash
stub_dir="$(cd "$(dirname "$0")" && pwd)"
svc=""; acct=""
shift
while [ $# -gt 0 ]; do
  case "$1" in
    -s) svc="$2"; shift 2 ;;
    -a) acct="$2"; shift 2 ;;
    -w) shift ;;
    *) shift ;;
  esac
done
printf '%s|%s\\n' "$svc" "$acct" >> "$stub_dir/calls"

if [ "$svc" = "com.aieo.aikeychain.managed" ]; then
  case "$acct" in
    MANAGED_KEY) printf '%s\\n' "managed-value"; exit 0 ;;
    MANAGED_EMPTY_KEY) exit 0 ;;
    MGERR_KEY) echo "interaction not allowed" >&2; exit 51 ;;
    MGHANG_KEY|HANG?_KEY) sleep 60 ;;
  esac
fi
exit 44
`;

before(async () => {
  stubDir = await mkdtemp(join(tmpdir(), 'akc-resolve-keychain-'));
  const stubPath = join(stubDir, 'security');
  callsPath = join(stubDir, 'calls');
  await writeFile(stubPath, STUB);
  await chmod(stubPath, 0o755);
  process.env.AIKEYCHAIN_SECURITY_BIN = stubPath;
  // 2000ms: 非ハング応答が並列テスト負荷でこの値を超えて timeout に誤分類される
  // フレークを避ける余裕（#185 再検証）。ハングテストは 60s stub を早く畳む。
  process.env.AIKEYCHAIN_SUBPROCESS_TIMEOUT_MS = '2000';
  ({ resolveKey, keyExists } = await import('../src/keychain.js'));
  ({ resolveRefs } = await import('../src/run.js'));
});

beforeEach(async () => {
  await writeFile(callsPath, '');
});

after(async () => {
  delete process.env.AIKEYCHAIN_SECURITY_BIN;
  delete process.env.AIKEYCHAIN_SUBPROCESS_TIMEOUT_MS;
  await rm(stubDir, { recursive: true, force: true });
});

test('resolveKey returns the managed value (single-tier lookup, #188)', async () => {
  assert.equal(await resolveKey('MANAGED_KEY'), 'managed-value');
  const calls = await readFile(callsPath, 'utf8');
  assert.equal(calls, 'com.aieo.aikeychain.managed|MANAGED_KEY\n');
});

test('resolveKey returns null when the key is not found (exit 44)', async () => {
  assert.equal(await resolveKey('NOPE_KEY'), null);
  const calls = await readFile(callsPath, 'utf8');
  assert.equal(calls, 'com.aieo.aikeychain.managed|NOPE_KEY\n');
});

test('resolveKey treats an empty successful value as authoritative failure', async () => {
  assert.equal(await resolveKey('MANAGED_EMPTY_KEY'), null);
});

test('resolveKey fails closed on a non-44 lookup error, with a reason (#147/#185 S4)', async () => {
  await assert.rejects(() => resolveKey('MGERR_KEY'), /reading "MGERR_KEY" failed \(exit 51\)/);
  const calls = await readFile(callsPath, 'utf8');
  assert.equal(calls, 'com.aieo.aikeychain.managed|MGERR_KEY\n');
});

test('keyExists reports existence for a managed key', async () => {
  const r = await keyExists('MANAGED_KEY');
  assert.equal(r.exists, true);
  assert.equal((await keyExists('NOPE_KEY')).exists, false);
});

test('keyExists fails closed (throws) on a non-44 probe error (#179 review S1)', async () => {
  await assert.rejects(() => keyExists('MGERR_KEY'), /keychain probe failed/);
});

test('a prompt-blocked read is killed and raises a locked-keychain error (#188)', async () => {
  const t0 = Date.now();
  await assert.rejects(() => resolveKey('MGHANG_KEY'), /locked|unavailable/);
  const elapsed = Date.now() - t0;
  // 有界: 60s の stub ハングに対し timeout(2000ms) + kill で返る。下限も検証。
  assert.ok(elapsed >= 1500, `should actually wait for the timeout (took ${elapsed}ms)`);
  assert.ok(elapsed < 10_000, `bounded well under the 60s hang (took ${elapsed}ms)`);
  const calls = await readFile(callsPath, 'utf8');
  assert.equal(calls, 'com.aieo.aikeychain.managed|MGHANG_KEY\n');
});

test('resolveRefs caches duplicate keys and enforces a command-level deadline (#185 S7)', async () => {
  const t0 = Date.now();
  const refs = [
    { varName: 'V1', keyName: 'HANG1_KEY' },
    { varName: 'V1B', keyName: 'HANG1_KEY' }, // 重複 — キャッシュで 2 回目は引かない
    { varName: 'V2', keyName: 'HANG2_KEY' },
    { varName: 'V3', keyName: 'HANG3_KEY' },
    { varName: 'V4', keyName: 'HANG4_KEY' },
    { varName: 'V5', keyName: 'HANG5_KEY' },
  ];
  const { resolved, failed } = await resolveRefs(refs);
  const elapsed = Date.now() - t0;
  assert.equal(Object.keys(resolved).length, 0);
  assert.equal(failed.length, 6);
  // deadline = timeout(2000ms) x 3 = 6s。5 個別キー x 2s = 10s を大きく下回る。
  assert.ok(elapsed < 12_000, `command-level deadline bounds the scan (took ${elapsed}ms)`);
  assert.ok(failed.some((f) => /deadline exceeded/.test(f.reason ?? '')));
  // 重複キーは 1 回しか解決を試みない（キャッシュ）: managed 1 段 x 1 回のみ
  const calls = await readFile(callsPath, 'utf8');
  const hang1Calls = calls.split('\n').filter((l) => l.endsWith('|HANG1_KEY')).length;
  assert.equal(hang1Calls, 1);
  const v1 = failed.find((f) => f.varName === 'V1');
  const v1b = failed.find((f) => f.varName === 'V1B');
  assert.equal(v1.reason, v1b.reason);
});
