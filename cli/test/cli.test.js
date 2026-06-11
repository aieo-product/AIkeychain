// CLI integration tests. A stub `security` command is placed first on PATH so
// these run without touching the real Keychain.
import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdtemp, writeFile, chmod } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const pExecFile = promisify(execFile);
const AKC = join(dirname(fileURLToPath(import.meta.url)), '..', 'bin', 'akc.js');

let stubDir;

// The stub knows one GUI-store key (GOOD_KEY), one manual key (MANUAL_KEY),
// and accepts interactive (-i) add-generic-password for NEW_KEY — but only
// when the value arrives via stdin as -X hex (never as argv).
const STUB = `#!/bin/bash
cmd="$1"; shift
if [ "$cmd" = "-i" ]; then
  read -r line
  case "$line" in
    add-generic-password*-a\\ \\"NEW_KEY\\"*-X\\ *)
      exit 0 ;;
    *)
      echo "stub -i: unexpected command: $line" >&2; exit 1 ;;
  esac
fi
svc=""; acct=""; want_value=false
while [ $# -gt 0 ]; do
  case "$1" in
    -s) svc="$2"; shift 2 ;;
    -a) acct="$2"; shift 2 ;;
    -w) want_value=true; shift ;;
    *) shift ;;
  esac
done
case "$cmd" in
  find-generic-password)
    if [ "$svc" = "com.aieo.aikeychain" ] && [ "$acct" = "GOOD_KEY" ]; then
      $want_value && echo "stub-good-value"; exit 0
    fi
    if [ "$svc" = "com.aieo.aikeychain" ] && [ "$acct" = "NEW_KEY" ]; then
      $want_value && echo "stub-new-value"; exit 0
    fi
    if [ "$svc" = "MANUAL_KEY" ]; then
      $want_value && echo "stub-manual-value"; exit 0
    fi
    exit 44 ;;
  add-generic-password)
    echo "stub: secret passed via argv — forbidden (issue #94)" >&2; exit 99 ;;
  *) exit 1 ;;
esac
`;

before(async () => {
  stubDir = await mkdtemp(join(tmpdir(), 'akc-stub-'));
  const stubPath = join(stubDir, 'security');
  await writeFile(stubPath, STUB);
  await chmod(stubPath, 0o755);
});

function runAkc(args, env = {}) {
  return pExecFile(process.execPath, [AKC, ...args], {
    env: { PATH: `${stubDir}:${process.env.PATH}`, ...env },
  }).then(
    (r) => ({ code: 0, ...r }),
    (e) => ({ code: e.code ?? 1, stdout: e.stdout ?? '', stderr: e.stderr ?? '' })
  );
}

test('version / help / unknown command', async () => {
  const v = await runAkc(['version']);
  assert.equal(v.code, 0);
  assert.match(v.stdout, /^akc \d+\.\d+\.\d+/);

  const h = await runAkc(['help']);
  assert.equal(h.code, 0);
  assert.match(h.stdout, /Usage:/);

  const bad = await runAkc(['nope']);
  assert.equal(bad.code, 1);
  assert.match(bad.stderr, /unknown command/);
});

test('run requires -- separator', async () => {
  const r = await runAkc(['run']);
  assert.equal(r.code, 1);
  assert.match(r.stderr, /missing '--' separator/);
});

test('run rejects unknown options', async () => {
  const r = await runAkc(['run', '--invalid-flag', '--', 'true']);
  assert.equal(r.code, 1);
  assert.match(r.stderr, /unknown option/);
});

test('run passes through when no refs exist', async () => {
  const r = await runAkc(['run', '--', 'echo', 'hello']);
  assert.equal(r.code, 0);
  assert.match(r.stdout, /hello/);
});

test('run resolves GUI-store and manual refs into the child env only', async () => {
  const r = await runAkc(
    ['run', '--', process.execPath, '-e', 'console.log(process.env.MY_TOKEN, process.env.OTHER)'],
    { MY_TOKEN: 'keychain://GOOD_KEY', OTHER: 'keychain://MANUAL_KEY' }
  );
  assert.equal(r.code, 0);
  assert.match(r.stdout, /stub-good-value stub-manual-value/);
});

test('run fails with exit 1 when a ref cannot be resolved', async () => {
  const r = await runAkc(['run', '--', 'true'], { MY_TOKEN: 'keychain://MISSING_KEY' });
  assert.equal(r.code, 1);
  assert.match(r.stderr, /MISSING_KEY not found/);
});

test('run --dry-run masks values and reports counts', async () => {
  const r = await runAkc(['run', '--dry-run'], {
    MY_TOKEN: 'keychain://GOOD_KEY',
    BAD: 'keychain://MISSING_KEY',
  });
  assert.equal(r.code, 0);
  assert.match(r.stdout, /\*{6} \(\d+ chars\)/);
  assert.doesNotMatch(r.stdout, /stub-good-value/);
  assert.match(r.stdout, /Resolved: 1, Failed: 1/);
});

test('run propagates the child exit code', async () => {
  const r = await runAkc(['run', '--', process.execPath, '-e', 'process.exit(3)']);
  assert.equal(r.code, 3);
});

test('run maps a signal-terminated child to 128+signum', async () => {
  const r = await runAkc([
    'run',
    '--',
    process.execPath,
    '-e',
    'process.kill(process.pid, "SIGTERM"); setTimeout(() => {}, 5000)',
  ]);
  assert.equal(r.code, 143); // 128 + SIGTERM(15)
});

test('check reports store and missing keys', async () => {
  const good = await runAkc(['check', 'GOOD_KEY']);
  assert.equal(good.code, 0);
  assert.match(good.stdout, /AI KeyChain store/);

  const missing = await runAkc(['check', 'NOPE_KEY']);
  assert.equal(missing.code, 1);
});

test('get prints a reference by default, raw value only with --reveal', async () => {
  const ref = await runAkc(['get', 'GOOD_KEY']);
  assert.equal(ref.code, 0);
  assert.equal(ref.stdout.trim(), 'keychain://GOOD_KEY');
  assert.doesNotMatch(ref.stdout, /stub-good-value/);

  const raw = await runAkc(['get', 'GOOD_KEY', '--reveal']);
  assert.equal(raw.code, 0);
  assert.equal(raw.stdout.trim(), 'stub-good-value');
});

test('set stores a piped value via security -i stdin, never argv', async () => {
  // The stub only accepts add-generic-password through -i (stdin) with -X hex;
  // an argv-based add-generic-password fails loudly (exit 99, issue #94).
  const r = await pExecFile(
    'bash',
    ['-c', `echo "piped-secret" | ${process.execPath} ${AKC} set NEW_KEY`],
    { env: { PATH: `${stubDir}:${process.env.PATH}` } }
  ).then(
    (r) => ({ code: 0, ...r }),
    (e) => ({ code: e.code ?? 1, stdout: e.stdout ?? '', stderr: e.stderr ?? '' })
  );
  assert.equal(r.code, 0);
  assert.match(r.stdout, /✅ Saved NEW_KEY/);
  assert.doesNotMatch(r.stdout, /piped-secret/);
});

test('set rejects invalid names and control characters before touching security', async () => {
  const badName = await pExecFile(
    'bash',
    ['-c', `echo "v" | ${process.execPath} ${AKC} set 'BAD KEY'`],
    { env: { PATH: `${stubDir}:${process.env.PATH}` } }
  ).then(
    () => ({ code: 0 }),
    (e) => ({ code: e.code ?? 1, stderr: e.stderr ?? '' })
  );
  assert.equal(badName.code, 1);
  assert.match(badName.stderr, /key name must match/);

  const ctrl = await pExecFile(
    'bash',
    ['-c', `printf 'line1\\nline2\\n' | ${process.execPath} ${AKC} set NEW_KEY`],
    { env: { PATH: `${stubDir}:${process.env.PATH}` } }
  ).then(
    () => ({ code: 0 }),
    (e) => ({ code: e.code ?? 1, stderr: e.stderr ?? '' })
  );
  assert.equal(ctrl.code, 1);
  assert.match(ctrl.stderr, /control characters/);
});
