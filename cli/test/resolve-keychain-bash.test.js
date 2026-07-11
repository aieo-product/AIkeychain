import { after, before, test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmod, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
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

if [ "$svc" = "com.aieo.aikeychain" ]; then
  printf '%s\\n' gui >> "$CALLS_PATH"
  case "$SCENARIO" in
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
  const start = script.indexOf('resolve_keychain() {');
  const end = script.indexOf('\n}\n\nmask_value()', start);
  assert.notEqual(start, -1, 'resolve_keychain function start must exist');
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
    `#!/bin/bash\nset -uo pipefail\nSECURITY_BIN="$1"\nCALLS_PATH="$2"\nSCENARIO="$3"\nexport CALLS_PATH SCENARIO\n${resolver}\nresolve_keychain TEST_KEY\n`
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

function runResolver(scenario) {
  const result = spawnSync('/bin/bash', [harnessPath, securityPath, callsPath, scenario], {
    encoding: 'utf8',
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
    calls: 'gui\n',
  });
});

test('scripts/akc resolve_keychain fails closed on successful empty GUI value', async () => {
  await assertScenario('gui_empty', {
    result: { status: 1, stdout: '', stderr: '' },
    calls: 'gui\n',
  });
});

test('scripts/akc resolve_keychain falls back to manual only on GUI exit 44', async () => {
  await assertScenario('gui_44_manual', {
    result: { status: 0, stdout: 'manual-value', stderr: '' },
    calls: 'gui\nmanual\n',
  });
});

test('scripts/akc resolve_keychain returns nonzero on GUI exit 44 and successful empty manual value', async () => {
  await assertScenario('gui_44_manual_empty', {
    result: { status: 1, stdout: '', stderr: '' },
    calls: 'gui\nmanual\n',
  });
});

test('scripts/akc resolve_keychain returns a nonempty GUI value without manual fallback', async () => {
  await assertScenario('gui_value', {
    result: { status: 0, stdout: 'gui-value', stderr: '' },
    calls: 'gui\n',
  });
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
  assert.match(result.stderr, /TEST_REF .* not found in Keychain/);
  assert.equal(await readFile(callsPath, 'utf8'), 'gui\nmanual\n');
});
