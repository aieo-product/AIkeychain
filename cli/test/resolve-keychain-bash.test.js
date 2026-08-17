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

// v2.0 (#188): scripts/akc resolves ONLY the managed namespace. The stub logs a
// "managed" line for the managed service and exits 44 for anything else.
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
    managed_hang) sleep 60 ;;
  esac
  exit 44
fi
exit 44
`;

const ENV_STUB = `#!/bin/bash
printf '%s\\n' 'TEST_REF=keychain://TEST_KEY'
`;

before(async () => {
  const script = await readFile(new URL('../../scripts/akc', import.meta.url), 'utf8');
  // security_bounded (#171) が resolve_keychain の依存なので、有界実行の定義
  // （タイムアウト変数から）ごと切り出す。
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

test('scripts/akc resolve_keychain returns the managed value (single tier, #188)', async () => {
  await assertScenario('managed_value', {
    result: { status: 0, stdout: 'managed-value', stderr: '' },
    calls: 'managed\n',
  });
});

test('scripts/akc resolve_keychain fails closed on managed exit 51', async () => {
  await assertScenario('managed_51', {
    result: { status: 51, stdout: '', stderr: '' },
    calls: 'managed\n',
  });
});

test('scripts/akc resolve_keychain returns nonzero on a successful empty value', async () => {
  await assertScenario('managed_empty', {
    result: { status: 1, stdout: '', stderr: '' },
    calls: 'managed\n',
  });
});

test('scripts/akc resolve_keychain returns 44 when not found', async () => {
  await assertScenario('none', {
    result: { status: 44, stdout: '', stderr: '' },
    calls: 'managed\n',
  });
});

test('scripts/akc resolve_keychain maps a managed timeout to 125 (locked keychain, #188)', async () => {
  await writeFile(callsPath, '');
  // シークレットを一時ファイル経由で運ばないことも検証 (#185 B1): 専用 TMPDIR に
  // 何も作られないこと。
  const isolatedTmp = await mkdtemp(join(tmpdir(), 'akc-b1-check-'));
  const t0 = Date.now();
  const result = runResolver('managed_hang', { AKC_SECURITY_TIMEOUT_SECS: '1', TMPDIR: isolatedTmp });
  const elapsed = Date.now() - t0;
  assert.equal(result.status, 125); // 有界失敗（ハングもプロンプトもしない）
  assert.equal(result.stdout, ''); // 値は漏れない
  assert.ok(elapsed >= 900, `should actually wait for the 1s timeout (took ${elapsed}ms)`);
  assert.ok(elapsed < 10_000, `bounded well under the 60s hang (took ${elapsed}ms)`);
  assert.equal(await readFile(callsPath, 'utf8'), 'managed\n');
  const leftover = await readdir(isolatedTmp);
  assert.deepEqual(leftover, [], 'no temp files may be created on the secret path (#185 B1)');
  await rm(isolatedTmp, { recursive: true, force: true });
});

test('scripts/akc neutralizes a hostile AKC_SECURITY_TIMEOUT_SECS (#185 B2: arithmetic injection)', async () => {
  await writeFile(callsPath, '');
  const canary = join(tmpdir(), `akc-b2-canary-${Date.now()}`);
  // $(( )) は配列添字のコマンド置換まで評価する — 検証が無いと任意コマンド実行
  const payload = `PATH[$(touch ${canary})]`;
  const result = runResolver('managed_value', { AKC_SECURITY_TIMEOUT_SECS: payload });
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
    [cmdHarnessPath, securityPath, callsPath, 'managed_51', envPath],
    { encoding: 'utf8' }
  );
  assert.equal(result.status, 0);
  assert.match(result.stdout, /Resolved: 0, Failed: 1/);
  // 非 44 の失敗は「not found」ではなく exit code 付きで報告する (#185 S4)
  assert.match(result.stderr, /TEST_REF .* keychain lookup failed \(exit 51\)/);
  assert.equal(await readFile(callsPath, 'utf8'), 'managed\n');
});
