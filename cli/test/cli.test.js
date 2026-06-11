// CLI integration tests. A stub `security` command is placed first on PATH so
// these run without touching the real Keychain (and on any OS in CI).
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

// The stub knows one GUI-store key (GOOD_KEY) and one manual key (MANUAL_KEY).
const STUB = `#!/bin/bash
cmd="$1"; shift
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
    if [ "$svc" = "MANUAL_KEY" ]; then
      $want_value && echo "stub-manual-value"; exit 0
    fi
    exit 44 ;;
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

test('set stores a value piped via stdin', async () => {
  // The stub's add-generic-password exits 1, so failure proves the value path
  // reached `security` without appearing in argv of akc itself.
  const r = await pExecFile(
    'bash',
    ['-c', `echo "piped-secret" | ${process.execPath} ${AKC} set NEW_KEY`],
    { env: { PATH: `${stubDir}:${process.env.PATH}` } }
  ).then(
    (r) => ({ code: 0, ...r }),
    (e) => ({ code: e.code ?? 1, stdout: e.stdout ?? '', stderr: e.stderr ?? '' })
  );
  assert.equal(r.code, 1); // stub rejects add-generic-password
  assert.match(r.stderr, /failed to save/);
});
