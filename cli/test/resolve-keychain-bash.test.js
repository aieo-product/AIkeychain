import { after, before, test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmod, mkdtemp, readdir, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

let tempDir;
let harnessPath;
let cmdHarnessPath;
let securityPath;
let envPath;
let callsPath;

const SECURITY_STUB = `#!/bin/bash
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

if [ "$svc" = "com.aieo.aikeychain.managed" ]; then
  printf '%s\\n' managed >> "$CALLS_PATH"
  case "$SCENARIO" in
    managed_value) printf '%s\\n' managed-value; exit 0 ;;
    managed_51) exit 51 ;;
    managed_empty) exit 0 ;;
    gui_hang) exit 44 ;;
    managed_hang) sleep 60 ;;
  esac
  exit 44
fi

if [ "$svc" = "com.aieo.aikeychain" ] && [ "$SCENARIO" = "gui_hang" ]; then
  printf '%s\\n' gui >> "$CALLS_PATH"
  sleep 60   # SecurityAgent プロンプト待ちを模す (#171)
  exit 0
fi

if [ "$svc" = "com.aieo.aikeychain" ]; then
  printf '%s\\n' gui >> "$CALLS_PATH"
  case "$SCENARIO" in
    managed_51) printf '%s\\n' stale-gui-value; exit 0 ;;
    gui_51) exit 51 ;;
    gui_empty) exit 0 ;;
    gui_44_manual) exit 44 ;;
    gui_44_manual_empty) exit 44 ;;
    manual_output_error) exit 44 ;;
    gui_value) printf '%s\\n' gui-value; exit 0 ;;
  esac
fi

printf '%s\\n' manual >> "$CALLS_PATH"
case "$SCENARIO" in
  gui_44_manual) printf '%s\\n' manual-value; exit 0 ;;
  gui_44_manual_empty) exit 0 ;;
  manual_output_error) printf '%s\\n' rejected-value; exit 52 ;;
  *) printf '%s\\n' manual-must-not-be-used; exit 0 ;;
esac
`;

const ENV_STUB = `#!/bin/bash
printf '%s\\n' 'TEST_REF=keychain://TEST_KEY'
`;

before(async () => {
  const script = await readFile(new URL('../../scripts/akc', import.meta.url), 'utf8');
  // security_bounded (#171) が resolve_keychain の依存になったため、有界実行の
  // 定義（タイムアウト変数から）ごと切り出す。
  const start = script.indexOf('AKC_SECURITY_TIMEOUT_SECS=');
  const end = script.indexOf('\n}\n\nmask_value()', start);
  assert.notEqual(start, -1, 'security_bounded prelude must exist');
  assert.notEqual(end, -1, 'resolve_keychain function end must exist');
  const resolver = script.slice(start, end + 2);
  const functionsEnd = script.indexOf('\n\n# Main dispatch', start);
  assert.notEqual(functionsEnd, -1, 'cmd_run function end must exist');
  const functions = script.slice(start, functionsEnd);

  tempDir = await mkdtemp(join(tmpdir(), 'akc-bash-resolver-'));
  harnessPath = join(tempDir, 'harness.sh');
  cmdHarnessPath = join(tempDir, 'cmd-harness.sh');
  securityPath = join(tempDir, 'security');
  envPath = join(tempDir, 'env');
  callsPath = join(tempDir, 'calls');
  await writeFile(
    harnessPath,
    `#!/bin/bash\nset -uo pipefail\nSECURITY_BIN="$1"\nCALLS_PATH="$2"\nSCENARIO="$3"\nAKC_SECURITY_TIMEOUT_SECS="\${AKC_SECURITY_TIMEOUT_SECS:-10}"\nexport CALLS_PATH SCENARIO\n${resolver}\nresolve_keychain TEST_KEY\n`
  );
  await writeFile(
    cmdHarnessPath,
    `#!/bin/bash\nset -euo pipefail\nSECURITY_BIN="$1"\nCALLS_PATH="$2"\nSCENARIO="$3"\nENV_BIN="$4"\nexport CALLS_PATH SCENARIO\n${functions}\ncmd_run --dry-run\n`
  );
  await writeFile(securityPath, SECURITY_STUB);
  await writeFile(envPath, ENV_STUB);
  await chmod(harnessPath, 0o755);
  await chmod(cmdHarnessPath, 0o755);
  await chmod(securityPath, 0o755);
  await chmod(envPath, 0o755);
});

after(async () => {
  await rm(tempDir, { recursive: true, force: true });
});

function runResolver(scenario, env = {}) {
  const result = spawnSync('/bin/bash', [harnessPath, securityPath, callsPath, scenario], {
    encoding: 'utf8',
    env: { ...process.env, ...env },
  });
  return { status: result.status, stdout: result.stdout, stderr: result.stderr };
}

async function assertScenario(scenario, expected) {
  await writeFile(callsPath, '');
  assert.deepEqual(runResolver(scenario), expected.result);
  assert.equal(await readFile(callsPath, 'utf8'), expected.calls);
}

test('scripts/akc resolve_keychain fails closed on GUI exit 51', async () => {
  await assertScenario('gui_51', {
    result: { status: 51, stdout: '', stderr: '' },
    calls: 'managed\ngui\n',
  });
});

test('scripts/akc resolve_keychain fails closed on successful empty GUI value', async () => {
  await assertScenario('gui_empty', {
    result: { status: 1, stdout: '', stderr: '' },
    calls: 'managed\ngui\n',
  });
});

test('scripts/akc resolve_keychain falls back to manual only on GUI exit 44', async () => {
  await assertScenario('gui_44_manual', {
    result: { status: 0, stdout: 'manual-value', stderr: '' },
    calls: 'managed\ngui\nmanual\n',
  });
});

test('scripts/akc resolve_keychain returns nonzero on GUI exit 44 and successful empty manual value', async () => {
  await assertScenario('gui_44_manual_empty', {
    result: { status: 1, stdout: '', stderr: '' },
    calls: 'managed\ngui\nmanual\n',
  });
});

test('scripts/akc resolve_keychain returns a nonempty GUI value without manual fallback', async () => {
  await assertScenario('gui_value', {
    result: { status: 0, stdout: 'gui-value', stderr: '' },
    calls: 'managed\ngui\n',
  });
});

test('scripts/akc resolve_keychain returns a managed value without legacy fallback (#167)', async () => {
  await assertScenario('managed_value', {
    result: { status: 0, stdout: 'managed-value', stderr: '' },
    calls: 'managed\n',
  });
});

test('scripts/akc resolve_keychain fails closed on managed exit 51 (#179 review B1)', async () => {
  // GUI 段は stale な値を返せる状態だが、managed の権威的失敗で止まること
  await assertScenario('managed_51', {
    result: { status: 51, stdout: '', stderr: '' },
    calls: 'managed\n',
  });
});

test('scripts/akc resolve_keychain fails closed on successful empty managed value', async () => {
  await assertScenario('managed_empty', {
    result: { status: 1, stdout: '', stderr: '' },
    calls: 'managed\n',
  });
});

test('scripts/akc resolve_keychain kills a prompt-blocked legacy read and returns 124 (#171)', async () => {
  await writeFile(callsPath, '');
  // シークレットを一時ファイル経由で運ばないことの検証 (#185 B1): 専用 TMPDIR を
  // 与え、実行後に何も残っていない（そもそも作られない）ことを確認する
  const isolatedTmp = await mkdtemp(join(tmpdir(), 'akc-b1-check-'));
  const t0 = Date.now();
  const result = runResolver('gui_hang', { AKC_SECURITY_TIMEOUT_SECS: '1', TMPDIR: isolatedTmp });
  const elapsed = Date.now() - t0;
  assert.equal(result.status, 124); // 有界失敗（ハングもプロンプトもしない）
  assert.equal(result.stdout, ''); // 値は漏れない
  assert.ok(elapsed >= 900, `should actually wait for the 1s timeout (took ${elapsed}ms)`);
  assert.ok(elapsed < 10_000, `bounded well under the 60s hang (took ${elapsed}ms)`);
  assert.equal(await readFile(callsPath, 'utf8'), 'managed\ngui\n');
  const leftover = await readdir(isolatedTmp);
  assert.deepEqual(leftover, [], 'no temp files may be created on the secret path (#185 B1)');
  await rm(isolatedTmp, { recursive: true, force: true });
});

test('scripts/akc resolve_keychain maps a managed-tier timeout to 125 (locked keychain, #185 S1)', async () => {
  await writeFile(callsPath, '');
  const t0 = Date.now();
  const result = runResolver('managed_hang', { AKC_SECURITY_TIMEOUT_SECS: '1' });
  const elapsed = Date.now() - t0;
  assert.equal(result.status, 125); // managed timeout は移行案内ではなくロック扱い
  assert.equal(result.stdout, '');
  assert.ok(elapsed >= 900 && elapsed < 10_000, `bounded (took ${elapsed}ms)`);
  assert.equal(await readFile(callsPath, 'utf8'), 'managed\n'); // fail-closed: レガシー段へ落ちない
});

test('scripts/akc neutralizes a hostile AKC_SECURITY_TIMEOUT_SECS (#185 B2: arithmetic injection)', async () => {
  await writeFile(callsPath, '');
  const canary = join(tmpdir(), `akc-b2-canary-${Date.now()}`);
  // $(( )) は配列添字のコマンド置換まで評価する — 検証が無いと任意コマンド実行
  const payload = `PATH[$(touch ${canary})]`;
  const result = runResolver('managed_value', { AKC_SECURITY_TIMEOUT_SECS: payload });
  // 注入は無害化され（既定 10s に fallback）、正常解決する
  assert.equal(result.status, 0);
  assert.equal(result.stdout, 'managed-value');
  let executed = true;
  try {
    await readFile(canary);
  } catch {
    executed = false;
  }
  assert.equal(executed, false, 'injected command must NOT run');
  await rm(canary, { force: true });
});

test('scripts/akc cmd_run rejects nonempty resolver output when its exit status is nonzero', async () => {
  await writeFile(callsPath, '');
  const result = spawnSync(
    '/bin/bash',
    [cmdHarnessPath, securityPath, callsPath, 'manual_output_error', envPath],
    { encoding: 'utf8' }
  );
  assert.equal(result.status, 0);
  assert.match(result.stdout, /Resolved: 0, Failed: 1/);
  assert.doesNotMatch(result.stdout, /rejected-value/);
  assert.doesNotMatch(result.stderr, /rejected-value/);
  // 非 44 の失敗は「not found」ではなく exit code 付きで報告する (#185 S4)
  assert.match(result.stderr, /TEST_REF .* keychain lookup failed \(exit 52\)/);
  assert.equal(await readFile(callsPath, 'utf8'), 'managed\ngui\nmanual\n');
});
