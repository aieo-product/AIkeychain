import { after, before, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { chmod, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

let resolveKey;
let keyExists;
let MigrationRequiredError;
let stubDir;
let callsPath;

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
    MGHANG_KEY) sleep 60 ;;
  esac
fi

if [ "$svc" = "com.aieo.aikeychain" ]; then
  case "$acct" in
    MGERR_KEY) printf '%s\\n' "stale-gui-value"; exit 0 ;;
    GUIHANG_KEY) sleep 60 ;;   # SecurityAgent プロンプト待ちを模す (#171)
  esac
fi

if [ "$svc" = "com.aieo.aikeychain" ]; then
  case "$acct" in
    ERROR_KEY) echo "interaction not allowed" >&2; exit 51 ;;
    EMPTY_KEY) exit 0 ;;
    MISSING_KEY) exit 44 ;;
    MANUAL_EMPTY_KEY) exit 44 ;;
    GUI_KEY) printf '%s\\n' "gui-value"; exit 0 ;;
  esac
fi

case "$svc" in
  ERROR_KEY) printf '%s\\n' "attacker-manual-value"; exit 0 ;;
  EMPTY_KEY) printf '%s\\n' "manual-must-not-be-used"; exit 0 ;;
  MISSING_KEY) printf '%s\\n' "manual-value"; exit 0 ;;
  MANUAL_EMPTY_KEY) exit 0 ;;
esac
exit 44
`;

before(async () => {
  stubDir = await mkdtemp(join(tmpdir(), 'akc-resolve-keychain-'));
  const stubPath = join(stubDir, 'security');
  callsPath = join(stubDir, 'calls');
  await writeFile(stubPath, STUB);
  await chmod(stubPath, 0o755);
  process.env.AIKEYCHAIN_SECURITY_BIN = stubPath;
  // ハング経路のテストを 60s 待たずに検証する（テスト専用オーバーライド / #171）
  process.env.AIKEYCHAIN_SUBPROCESS_TIMEOUT_MS = '500';
  ({ resolveKey, keyExists, MigrationRequiredError } = await import('../src/keychain.js'));
});

beforeEach(async () => {
  await writeFile(callsPath, '');
});

after(async () => {
  delete process.env.AIKEYCHAIN_SECURITY_BIN;
  delete process.env.AIKEYCHAIN_SUBPROCESS_TIMEOUT_MS;
  await rm(stubDir, { recursive: true, force: true });
});

test('resolveKey fails closed on a non-44 GUI lookup error (#147)', async () => {
  assert.equal(await resolveKey('ERROR_KEY'), null);
  const calls = await readFile(callsPath, 'utf8');
  assert.equal(calls, 'com.aieo.aikeychain.managed|ERROR_KEY\ncom.aieo.aikeychain|ERROR_KEY\n');
});

test('resolveKey falls back to manual storage when GUI lookup exits 44', async () => {
  assert.equal(await resolveKey('MISSING_KEY'), 'manual-value');
});

test('resolveKey returns null when GUI lookup exits 44 and manual value is empty', async () => {
  assert.equal(await resolveKey('MANUAL_EMPTY_KEY'), null);
});

test('resolveKey treats an empty successful GUI value as authoritative failure', async () => {
  assert.equal(await resolveKey('EMPTY_KEY'), null);
  const calls = await readFile(callsPath, 'utf8');
  assert.equal(calls, 'com.aieo.aikeychain.managed|EMPTY_KEY\ncom.aieo.aikeychain|EMPTY_KEY\n');
});

test('resolveKey returns the GUI storage value without manual fallback', async () => {
  assert.equal(await resolveKey('GUI_KEY'), 'gui-value');
});

test('resolveKey returns the managed value without touching legacy tiers (#167)', async () => {
  assert.equal(await resolveKey('MANAGED_KEY'), 'managed-value');
  const calls = await readFile(callsPath, 'utf8');
  assert.equal(calls, 'com.aieo.aikeychain.managed|MANAGED_KEY\n');
});

test('resolveKey fails closed on a non-44 managed lookup error (#179 review)', async () => {
  // GUI 段には stale な値が存在するが、managed 段の権威的失敗 (exit 51) で
  // チェーンは止まらなければならない（#150 の GUI 応答=権威と同じ原則）。
  assert.equal(await resolveKey('MGERR_KEY'), null);
  const calls = await readFile(callsPath, 'utf8');
  assert.equal(calls, 'com.aieo.aikeychain.managed|MGERR_KEY\n');
});

test('resolveKey treats an empty successful managed value as authoritative failure', async () => {
  assert.equal(await resolveKey('MANAGED_EMPTY_KEY'), null);
  const calls = await readFile(callsPath, 'utf8');
  assert.equal(calls, 'com.aieo.aikeychain.managed|MANAGED_EMPTY_KEY\n');
});

test('keyExists reports the managed store', async () => {
  const r = await keyExists('MANAGED_KEY');
  assert.equal(r.managed, true);
  assert.equal(r.app, false);
  assert.equal(r.manual, false);
  assert.equal(r.exists, true);
});

test('keyExists fails closed (throws) on a non-44 probe error (#179 review S1)', async () => {
  await assert.rejects(() => keyExists('MGERR_KEY'), /keychain probe failed/);
});

test('a prompt-blocked legacy read is killed and raises MigrationRequiredError (#171)', async () => {
  const t0 = Date.now();
  await assert.rejects(
    () => resolveKey('GUIHANG_KEY'),
    (err) => {
      assert.ok(err instanceof MigrationRequiredError);
      assert.match(err.message, /migrat/i);
      assert.match(err.message, /akc set GUIHANG_KEY/);
      return true;
    }
  );
  // 有界: 60s の stub ハングに対し timeout(500ms) + kill で返る
  assert.ok(Date.now() - t0 < 10_000);
  const calls = await readFile(callsPath, 'utf8');
  assert.equal(calls, 'com.aieo.aikeychain.managed|GUIHANG_KEY\ncom.aieo.aikeychain|GUIHANG_KEY\n');
});

test('a managed-tier timeout raises a locked-keychain error, not migration guidance (#171)', async () => {
  const t0 = Date.now();
  await assert.rejects(
    () => resolveKey('MGHANG_KEY'),
    (err) => {
      assert.ok(!(err instanceof MigrationRequiredError)); // managed は所有問題ではない
      assert.match(err.message, /locked|unavailable/);
      return true;
    }
  );
  assert.ok(Date.now() - t0 < 10_000);
  // fail-closed: レガシー段へは落ちない
  const calls = await readFile(callsPath, 'utf8');
  assert.equal(calls, 'com.aieo.aikeychain.managed|MGHANG_KEY\n');
});
