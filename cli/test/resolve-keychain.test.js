import { after, before, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { chmod, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

let resolveKey;
let keyExists;
let resolveRefs;
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
    GUIHANG_KEY|HANG?_KEY) sleep 60 ;;   # SecurityAgent プロンプト待ちを模す (#171)
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
  // ハング経路のテストを 60s 待たずに検証する（テスト専用オーバーライド / #171）。
  // 2000ms: 非ハングの stub 応答が並列テスト負荷でこの値を超えて fail-closed
  // 検証が timeout 分類に化けるフレークを避ける余裕を取る（#185 再検証の指摘）。
  process.env.AIKEYCHAIN_SUBPROCESS_TIMEOUT_MS = '2000';
  ({ resolveKey, keyExists, MigrationRequiredError } = await import('../src/keychain.js'));
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

test('resolveKey fails closed on a non-44 GUI lookup error, with a reason (#147/#185 S4)', async () => {
  // manual 段には攻撃者値が待ち構えているが、GUI 段の権威的失敗 (exit 51) で
  // チェーンは止まる。null で「無い」と偽るのではなく理由を説明して throw する。
  await assert.rejects(() => resolveKey('ERROR_KEY'), /legacy GUI store failed \(exit 51\)/);
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
  await assert.rejects(() => resolveKey('MGERR_KEY'), /managed namespace failed \(exit 51\)/);
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
  // 有界: 60s の stub ハングに対し timeout(500ms) + kill で返る。
  // 下限も検証 — 即時失敗するようなら timeout ではなく別の壊れ方をしている
  const elapsed = Date.now() - t0;
  assert.ok(elapsed >= 400, `should actually wait for the timeout (took ${elapsed}ms)`);
  assert.ok(elapsed < 10_000, `bounded well under the 60s hang (took ${elapsed}ms)`);
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
  const elapsed = Date.now() - t0;
  assert.ok(elapsed >= 400 && elapsed < 10_000, `bounded (took ${elapsed}ms)`);
  // fail-closed: レガシー段へは落ちない
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
  // deadline = timeout(2000ms) x 3 = 6s が効き、5 キーを無制限に直列待ちしない。
  // 最初のキー(managed+gui の 2 段ハング ~4s)後に deadline 超過し残りは skip。
  // 上限は並列テスト負荷のマージン込み。本質の検証は下の skip 理由の存在
  assert.ok(elapsed < 14_000, `command-level deadline bounds the scan (took ${elapsed}ms)`);
  // 後半のキーは deadline 超過でスキップされ、その旨の理由を持つ
  assert.ok(failed.some((f) => /deadline exceeded/.test(f.reason ?? '')));
  // 重複キーは 1 回しか解決を試みない（キャッシュ）
  const calls = await readFile(callsPath, 'utf8');
  const hang1Calls = calls.split('\n').filter((l) => l.endsWith('|HANG1_KEY')).length;
  assert.equal(hang1Calls, 2); // managed + GUI の 2 段 x 1 回のみ
  // どちらの失敗も同じ理由を共有する
  const v1 = failed.find((f) => f.varName === 'V1');
  const v1b = failed.find((f) => f.varName === 'V1B');
  assert.equal(v1.reason, v1b.reason);
});
