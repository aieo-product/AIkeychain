// Keychain *access* failures vs. genuinely missing keys.
//
// Measured on a real host (Codex `workspace-write` sandbox, 2026-10-05): a
// metadata lookup of an EXISTING managed key exits 44 and prints BOTH
//   SecKeychainSearchCreateFromAttributes: One or more parameters passed to a function were not valid.
//   SecKeychainSearchCopyNext: The specified item could not be found in the keychain.
// A genuine miss prints only the second line. Treating every exit 44 as "not
// found" misreported existing keys; these tests pin the distinction and that a
// failed lookup never runs the requested workload.
import { after, before, test } from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { chmod, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const pExecFile = promisify(execFile);
const AKC = fileURLToPath(new URL('../bin/akc.js', import.meta.url));

const SEARCH_ERR =
  'security: SecKeychainSearchCreateFromAttributes: One or more parameters passed to a function were not valid.';
const NOT_FOUND =
  'security: SecKeychainSearchCopyNext: The specified item could not be found in the keychain.';

// STUB_MODE=sandbox    every lookup fails the search (dirty 44); dump is empty.
// STUB_MODE=hexnoise   dirty 44 whose stderr carries a long hex run.
// otherwise            GOOD_KEY exists; anything else is a clean 44.
const STUB = `#!/bin/bash
cmd="$1"; shift
acct=""; want_value=false
while [ $# -gt 0 ]; do
  case "$1" in
    -a) acct="$2"; shift 2 ;;
    -w) want_value=true; shift ;;
    *) shift ;;
  esac
done
case "$cmd" in
  find-generic-password|delete-generic-password)
    if [ "$STUB_MODE" = "sandbox" ]; then
      echo "${SEARCH_ERR}" >&2; echo "${NOT_FOUND}" >&2; exit 44
    fi
    if [ "$STUB_MODE" = "hexnoise" ]; then
      echo "security: weird failure 0123456789abcdef0123456789abcdef" >&2; exit 44
    fi
    if [ "$acct" = "GOOD_KEY" ]; then $want_value && echo "stub-good-value"; exit 0; fi
    echo "${NOT_FOUND}" >&2; exit 44 ;;
  dump-keychain)
    [ "$STUB_MODE" = "sandbox" ] && exit 0
    printf '%s\\n' 'keychain: "/x/login.keychain-db"' 'class: "genp"' '    "acct"<blob>="GOOD_KEY"' '    "svce"<blob>="com.aieo.aikeychain.managed"'
    exit 0 ;;
  *) exit 1 ;;
esac
`;

let stubDir;

before(async () => {
  stubDir = await mkdtemp(join(tmpdir(), 'akc-access-'));
  await writeFile(join(stubDir, 'security'), STUB);
  await chmod(join(stubDir, 'security'), 0o755);
});

after(async () => {
  await rm(stubDir, { recursive: true, force: true });
});

function runAkc(args, env = {}) {
  return pExecFile(process.execPath, [AKC, ...args], {
    env: {
      PATH: process.env.PATH,
      HOME: stubDir, // doctor reads ~/.codex, ~/.claude.json, ~/.zshrc — keep it hermetic
      AIKEYCHAIN_SECURITY_BIN: join(stubDir, 'security'),
      AIKEYCHAIN_SUBPROCESS_TIMEOUT_MS: '5000',
      ...env,
    },
  }).then(
    (r) => ({ code: 0, ...r }),
    (e) => ({ code: e.code ?? 1, stdout: e.stdout ?? '', stderr: e.stderr ?? '' })
  );
}

const ACCESS = /Keychain search itself failed/;

test('classifyExit44: only a pure not-found stderr is a miss', async () => {
  const { classifyExit44 } = await import('../src/keychain.js');
  assert.deepEqual(classifyExit44(''), { notFound: true });
  assert.deepEqual(classifyExit44(`${NOT_FOUND}\n`), { notFound: true });
  const c = classifyExit44(`${SEARCH_ERR}\n${NOT_FOUND}\n`);
  assert.equal(c.notFound, false);
  assert.match(c.detail, /SecKeychainSearchCreateFromAttributes/);
});

test('check: a genuinely missing key is still "not found"', async () => {
  const r = await runAkc(['check', 'MISSING_KEY']);
  assert.equal(r.code, 1);
  assert.match(r.stdout, /MISSING_KEY not found/);
});

test('check: an existing key succeeds when access works', async () => {
  const r = await runAkc(['check', 'GOOD_KEY']);
  assert.equal(r.code, 0);
  assert.match(r.stdout, /GOOD_KEY exists/);
});

test('check: a failed search is reported as an access failure, never "not found"', async () => {
  const r = await runAkc(['check', 'GOOD_KEY'], { STUB_MODE: 'sandbox' });
  assert.equal(r.code, 1);
  assert.match(r.stderr, ACCESS);
  assert.doesNotMatch(r.stdout + r.stderr, /not found in Keychain/);
});

test('run: a failed search never starts the child', async () => {
  const marker = join(stubDir, 'child-ran');
  const r = await runAkc(
    ['run', '--', process.execPath, '-e', `require('fs').writeFileSync(${JSON.stringify(marker)}, 'x')`],
    { STUB_MODE: 'sandbox', MY_TOKEN: 'keychain://GOOD_KEY' }
  );
  assert.equal(r.code, 1);
  assert.match(r.stderr, ACCESS);
  assert.doesNotMatch(r.stderr, /GOOD_KEY not found/);
  await assert.rejects(readFile(marker), 'child must not run');
});

test('run --dry-run: access failure gets the sandbox hint, not "register missing keys"', async () => {
  const r = await runAkc(['run', '--dry-run'], { STUB_MODE: 'sandbox', MY_TOKEN: 'keychain://GOOD_KEY' });
  assert.match(r.stdout, /Failed: 1/);
  assert.match(r.stdout, /could not be searched from this process/);
  assert.doesNotMatch(r.stdout, /Register missing keys/);
});

test('get --reveal: access failure prints no value and is not "not found"', async () => {
  const r = await runAkc(['get', 'GOOD_KEY', '--reveal'], { STUB_MODE: 'sandbox' });
  assert.equal(r.code, 1);
  assert.equal(r.stdout, '');
  assert.match(r.stderr, ACCESS);
});

test('list: an empty dump in a restricted process is an error, not "no keys"', async () => {
  const r = await runAkc(['list'], { STUB_MODE: 'sandbox' });
  assert.equal(r.code, 1);
  assert.match(r.stderr, ACCESS);
});

test('doctor: keychain access is reported as failing in a restricted process', async () => {
  const r = await runAkc(['doctor'], { STUB_MODE: 'sandbox' });
  assert.match(r.stdout + r.stderr, /keychain access/);
  assert.match(r.stdout + r.stderr, ACCESS);
});

test('doctor: keychain access passes when the probe sees a clean miss', async () => {
  const r = await runAkc(['doctor']);
  assert.doesNotMatch(r.stdout + r.stderr, ACCESS);
  assert.match(r.stdout + r.stderr, /1 key\(s\) in the managed namespace/);
});

test('delete: a failed search is an error, not an idempotent "already gone"', async () => {
  const r = await runAkc(['delete', 'GOOD_KEY', '--yes'], { STUB_MODE: 'sandbox' });
  assert.equal(r.code, 1);
  assert.match(r.stderr, ACCESS);
});

test('access errors redact hex-like material from security stderr', async () => {
  const r = await runAkc(['check', 'GOOD_KEY'], { STUB_MODE: 'hexnoise' });
  assert.equal(r.code, 1);
  assert.match(r.stderr, ACCESS);
  assert.doesNotMatch(r.stderr, /0123456789abcdef0123456789abcdef/);
});
