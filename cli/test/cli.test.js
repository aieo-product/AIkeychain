// CLI integration tests. A stub `security` command is pointed to via
// AIKEYCHAIN_SECURITY_BIN (the test-only override for the hardcoded
// /usr/bin/security default, issue #117) so these run without touching the
// real Keychain.
import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdtemp, writeFile, chmod, access } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const pExecFile = promisify(execFile);
const AKC = join(dirname(fileURLToPath(import.meta.url)), '..', 'bin', 'akc.js');

let stubDir;

// The stub knows one GUI-store key (GOOD_KEY) and one manual key (MANUAL_KEY).
// Interactive (-i) add-generic-password is accepted only with -X hex via stdin
// (never argv): NEW_KEY round-trips through a state file so read-back
// verification sees the value actually written; ECHO_KEY simulates a failure
// whose stderr leaks the full command line including the hex value.
const STUB = `#!/bin/bash
state_dir="$(cd "$(dirname "$0")" && pwd)"
cmd="$1"; shift
if [ "$cmd" = "-i" ]; then
  read -r line
  case "$line" in
    add-generic-password*-a\\ \\"NEW_KEY\\"*-X\\ *)
      # The managed namespace is the ONLY legal write target (#167). A write
      # to any other service must fail loudly so tests catch a wrong -s.
      case "$line" in
        *-s\\ \\"com.aieo.aikeychain.managed\\"*) ;;
        *) echo "stub -i: write outside the managed namespace: $line" >&2; exit 98 ;;
      esac
      printf '%s' "\${line##* }" | xxd -r -p > "$state_dir/state-NEW_KEY"
      exit 0 ;;
    add-generic-password*-a\\ \\"ECHO_KEY\\"*-X\\ *)
      echo "security: SecKeychainItemCreateFromContent failed: $line" >&2
      exit 1 ;;
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
    if [ "$svc" = "com.aieo.aikeychain.managed" ] && [ "$acct" = "NEW_KEY" ] && [ -f "$state_dir/state-NEW_KEY" ]; then
      $want_value && { cat "$state_dir/state-NEW_KEY"; echo; }; exit 0
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
    env: { PATH: process.env.PATH, AIKEYCHAIN_SECURITY_BIN: join(stubDir, 'security'), ...env },
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

test('a `security` stub on PATH is ignored when the override is unset (issue #117)', async () => {
  // The actual fix: even with a hostile `security` first on PATH, the CLI must
  // invoke the hardcoded absolute /usr/bin/security and never the PATH stub.
  // (execFile with an absolute path does not search PATH, so this holds even on
  // platforms where /usr/bin/security is absent — the stub is simply never run.)
  const hijackDir = await mkdtemp(join(tmpdir(), 'akc-hijack-'));
  const marker = join(hijackDir, 'INVOKED');
  const hijack = join(hijackDir, 'security');
  await writeFile(hijack, `#!/bin/bash\ntouch "${marker}"\nexit 0\n`);
  await chmod(hijack, 0o755);

  // Read-only command, hijack dir first on PATH, and crucially NO
  // AIKEYCHAIN_SECURITY_BIN override.
  await pExecFile(process.execPath, [AKC, 'check', 'DEFINITELY_NOT_A_REAL_KEY_117'], {
    env: { PATH: `${hijackDir}:${process.env.PATH}` },
  }).catch(() => {});

  let stubWasInvoked = true;
  try {
    await access(marker);
  } catch {
    stubWasInvoked = false;
  }
  assert.equal(stubWasInvoked, false, 'PATH `security` stub was executed — absolute path not enforced');
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
  assert.match(r.stdout, /\*{8}/); // 固定長マスク
  assert.doesNotMatch(r.stdout, /\d+ chars/); // 桁数は漏らさない (#115/#123 統一)
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

test('check on a store-only key hints the correct `security` form (issue #137)', async () => {
  // GOOD_KEY exists only under service="com.aieo.aikeychain" account="GOOD_KEY"
  // (the stub reports it found ONLY for that query, not for the bare -s
  // GOOD_KEY form). That mismatch is exactly the #137 false-negative: an agent
  // running `security find-generic-password -s "GOOD_KEY" -w` gets exit 44 and
  // wrongly concludes the key is unregistered. `akc check` must append a hint
  // so the correct two-attribute form (or `akc get`) is discoverable.
  const good = await runAkc(['check', 'GOOD_KEY']);
  assert.equal(good.code, 0);
  assert.match(good.stdout, /-s "com\.aieo\.aikeychain" -a "GOOD_KEY" -w/);
  assert.match(good.stdout, /akc get GOOD_KEY/);

  // A manual-only key must NOT get the hint — the bare `-s <KEY>` form already
  // works for it, so the extra line would be noise.
  const manual = await runAkc(['check', 'MANUAL_KEY']);
  assert.equal(manual.code, 0);
  assert.match(manual.stdout, /manual entry/);
  assert.doesNotMatch(manual.stdout, /security CLI: use/);
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
    { env: { PATH: process.env.PATH, AIKEYCHAIN_SECURITY_BIN: join(stubDir, 'security') } }
  ).then(
    (r) => ({ code: 0, ...r }),
    (e) => ({ code: e.code ?? 1, stdout: e.stdout ?? '', stderr: e.stderr ?? '' })
  );
  assert.equal(r.code, 0);
  assert.match(r.stdout, /✅ Saved NEW_KEY/);
  assert.doesNotMatch(r.stdout, /piped-secret/);
});

test('set failure stderr never leaks the value, even when security echoes the command', async () => {
  const value = 'echo-secret-value';
  const hex = Buffer.from(value, 'utf8').toString('hex');
  const r = await pExecFile(
    'bash',
    ['-c', `printf '%s' "${value}" | ${process.execPath} ${AKC} set ECHO_KEY`],
    { env: { PATH: process.env.PATH, AIKEYCHAIN_SECURITY_BIN: join(stubDir, 'security') } }
  ).then(
    () => ({ code: 0, stdout: '', stderr: '' }),
    (e) => ({ code: e.code ?? 1, stdout: e.stdout ?? '', stderr: e.stderr ?? '' })
  );
  assert.equal(r.code, 1);
  assert.match(r.stderr, /failed to save/);
  assert.doesNotMatch(r.stderr, new RegExp(value));
  assert.doesNotMatch(r.stderr, new RegExp(hex, 'i'));
  assert.match(r.stderr, /<redacted>/);
});

test('set rejects invalid names and control characters before touching security', async () => {
  const badName = await pExecFile(
    'bash',
    ['-c', `echo "v" | ${process.execPath} ${AKC} set 'BAD KEY'`],
    { env: { PATH: process.env.PATH, AIKEYCHAIN_SECURITY_BIN: join(stubDir, 'security') } }
  ).then(
    () => ({ code: 0 }),
    (e) => ({ code: e.code ?? 1, stderr: e.stderr ?? '' })
  );
  assert.equal(badName.code, 1);
  assert.match(badName.stderr, /key name must match/);

  const ctrl = await pExecFile(
    'bash',
    ['-c', `printf 'line1\\nline2\\n' | ${process.execPath} ${AKC} set NEW_KEY`],
    { env: { PATH: process.env.PATH, AIKEYCHAIN_SECURITY_BIN: join(stubDir, 'security') } }
  ).then(
    () => ({ code: 0 }),
    (e) => ({ code: e.code ?? 1, stderr: e.stderr ?? '' })
  );
  assert.equal(ctrl.code, 1);
  assert.match(ctrl.stderr, /printable ASCII/);
});

test('set stores an all-hex ASCII secret verbatim (#179 review: no hex-decode guessing)', async () => {
  const r = await pExecFile(
    'bash',
    ['-c', `printf '4142434445464748' | ${process.execPath} ${AKC} set NEW_KEY`],
    { env: { PATH: process.env.PATH, AIKEYCHAIN_SECURITY_BIN: join(stubDir, 'security') } }
  ).then(
    (r) => ({ code: 0, ...r }),
    (e) => ({ code: e.code ?? 1, stdout: e.stdout ?? '', stderr: e.stderr ?? '' })
  );
  assert.equal(r.code, 0);

  const back = await runAkc(['get', 'NEW_KEY', '--reveal']);
  assert.equal(back.code, 0);
  // 値がそのまま返ること — "ABCDEFGH" に化けたら hex 推測復号が復活している
  assert.equal(back.stdout.trim(), '4142434445464748');
});

test('set rejects non-ASCII values until the C7 encoding convention lands', async () => {
  const r = await pExecFile(
    'bash',
    ['-c', `printf '秘密のトークン' | ${process.execPath} ${AKC} set NEW_KEY`],
    { env: { PATH: process.env.PATH, AIKEYCHAIN_SECURITY_BIN: join(stubDir, 'security') } }
  ).then(
    () => ({ code: 0 }),
    (e) => ({ code: e.code ?? 1, stderr: e.stderr ?? '' })
  );
  assert.equal(r.code, 1);
  assert.match(r.stderr, /printable ASCII/);
});

test('set --manual is rejected (#167: managed namespace is the only write target)', async () => {
  const r = await pExecFile(
    'bash',
    ['-c', `echo "v" | ${process.execPath} ${AKC} set NEW_KEY --manual`],
    { env: { PATH: process.env.PATH, AIKEYCHAIN_SECURITY_BIN: join(stubDir, 'security') } }
  ).then(
    () => ({ code: 0 }),
    (e) => ({ code: e.code ?? 1, stderr: e.stderr ?? '' })
  );
  assert.equal(r.code, 1);
  assert.match(r.stderr, /--manual is no longer supported/);
});

test('check shows the managed store and hints the managed `security` form', async () => {
  // NEW_KEY was stored to the managed namespace by the earlier set test
  const r = await runAkc(['check', 'NEW_KEY']);
  assert.equal(r.code, 0);
  assert.match(r.stdout, /managed store/);
  assert.doesNotMatch(r.stdout, /exists \(\)/); // 空括弧にならない (#179 S2)
  assert.match(r.stdout, /-s "com\.aieo\.aikeychain\.managed" -a "NEW_KEY" -w/);
});
