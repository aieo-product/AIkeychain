// deleteKey semantics (v2.0 #188): managed namespace only.
//   - returns true when an item was removed
//   - returns false on exit 44 (not found / idempotent)
//   - throws on any other failure
import { after, before, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { chmod, mkdtemp, readFile, rm, writeFile, access } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

let deleteKey;
let stubDir;
let callsPath;

const STUB = `#!/bin/bash
dir="$(cd "$(dirname "$0")" && pwd)"
cmd="$1"; shift
svc=""; acct=""
while [ $# -gt 0 ]; do case "$1" in
  -s) svc="$2"; shift 2 ;;
  -a) acct="$2"; shift 2 ;;
  *) shift ;;
esac; done
[ "$cmd" = "delete-generic-password" ] || exit 1
printf '%s|%s\\n' "$svc" "$acct" >> "$dir/calls"
[ "$svc" = "com.aieo.aikeychain.managed" ] || exit 1
case "$acct" in
  FAIL_KEY) echo "denied" >&2; exit 51 ;;
esac
if [ -f "$dir/managed-$acct" ]; then rm "$dir/managed-$acct"; exit 0; fi
exit 44
`;

before(async () => {
  stubDir = await mkdtemp(join(tmpdir(), 'akc-delete-keychain-'));
  const stubPath = join(stubDir, 'security');
  callsPath = join(stubDir, 'calls');
  await writeFile(stubPath, STUB);
  await chmod(stubPath, 0o755);
  process.env.AIKEYCHAIN_SECURITY_BIN = stubPath;
  ({ deleteKey } = await import('../src/keychain.js'));
});

beforeEach(async () => {
  await writeFile(callsPath, '');
});

after(async () => {
  delete process.env.AIKEYCHAIN_SECURITY_BIN;
  await rm(stubDir, { recursive: true, force: true });
});

const exists = (name) => access(join(stubDir, name)).then(() => true, () => false);

test('deleteKey removes the managed item and returns true', async () => {
  await writeFile(join(stubDir, 'managed-MY_KEY'), '');
  assert.equal(await deleteKey('MY_KEY'), true);
  assert.equal(await exists('managed-MY_KEY'), false);
  assert.equal((await readFile(callsPath, 'utf8')).trim(), 'com.aieo.aikeychain.managed|MY_KEY');
});

test('deleteKey returns false when the key is not found (idempotent, exit 44)', async () => {
  assert.equal(await deleteKey('NOT_THERE_KEY'), false);
});

test('deleteKey throws on a non-44 failure', async () => {
  await assert.rejects(() => deleteKey('FAIL_KEY'), /failed to delete/);
});

test('deleteKey only ever touches the managed namespace', async () => {
  await writeFile(join(stubDir, 'managed-K'), '');
  await deleteKey('K');
  const calls = (await readFile(callsPath, 'utf8')).trim().split('\n');
  assert.deepEqual(calls, ['com.aieo.aikeychain.managed|K']);
});
