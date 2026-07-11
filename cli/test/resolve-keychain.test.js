import { after, before, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { chmod, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

let resolveKey;
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

if [ "$svc" = "com.aieo.aikeychain" ]; then
  case "$acct" in
    ERROR_KEY) echo "interaction not allowed" >&2; exit 51 ;;
    EMPTY_KEY) exit 0 ;;
    MISSING_KEY) exit 44 ;;
    GUI_KEY) printf '%s\\n' "gui-value"; exit 0 ;;
  esac
fi

case "$svc" in
  ERROR_KEY) printf '%s\\n' "attacker-manual-value"; exit 0 ;;
  EMPTY_KEY) printf '%s\\n' "manual-must-not-be-used"; exit 0 ;;
  MISSING_KEY) printf '%s\\n' "manual-value"; exit 0 ;;
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
  ({ resolveKey } = await import('../src/keychain.js'));
});

beforeEach(async () => {
  await writeFile(callsPath, '');
});

after(async () => {
  delete process.env.AIKEYCHAIN_SECURITY_BIN;
  await rm(stubDir, { recursive: true, force: true });
});

test('resolveKey fails closed on a non-44 GUI lookup error (#147)', async () => {
  assert.equal(await resolveKey('ERROR_KEY'), null);
  const calls = await readFile(callsPath, 'utf8');
  assert.equal(calls, 'com.aieo.aikeychain|ERROR_KEY\n');
});

test('resolveKey falls back to manual storage when GUI lookup exits 44', async () => {
  assert.equal(await resolveKey('MISSING_KEY'), 'manual-value');
});

test('resolveKey treats an empty successful GUI value as authoritative failure', async () => {
  assert.equal(await resolveKey('EMPTY_KEY'), null);
  const calls = await readFile(callsPath, 'utf8');
  assert.equal(calls, 'com.aieo.aikeychain|EMPTY_KEY\n');
});

test('resolveKey returns the GUI storage value without manual fallback', async () => {
  assert.equal(await resolveKey('GUI_KEY'), 'gui-value');
});
