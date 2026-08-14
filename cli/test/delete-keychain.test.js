// deleteKey semantics (#179 second-stage review B3/B4):
//   - fallback stores (manual -> legacy GUI) are cleaned BEFORE the managed copy
//   - manual duplicates are deleted until exit 44 (first-match-only otherwise, #100)
//   - a non-44 failure aborts with the managed copy intact (no resurrection)
//   - non-env-var-shaped names never touch the manual tier (other apps' items)
import { after, before, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { chmod, mkdtemp, readFile, rm, writeFile, access } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

let deleteKey;
let stubDir;
let callsPath;

// State model: file "managed-<acct>" / "gui-<acct>" exists -> one deletable
// item; file "manual-<svc>" holds a duplicate counter (issue #100 scenario).
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
case "$svc" in
  com.aieo.aikeychain)
    case "$acct" in
      LEGACY_FAIL_KEY) echo "denied" >&2; exit 51 ;;
    esac
    if [ -f "$dir/gui-$acct" ]; then rm "$dir/gui-$acct"; exit 0; fi
    exit 44 ;;
  com.aieo.aikeychain.managed)
    if [ -f "$dir/managed-$acct" ]; then rm "$dir/managed-$acct"; exit 0; fi
    exit 44 ;;
  *)
    f="$dir/manual-$svc"
    if [ -f "$f" ]; then
      n=$(cat "$f")
      if [ "$n" -gt 1 ]; then echo $((n-1)) > "$f"; else rm "$f"; fi
      exit 0
    fi
    exit 44 ;;
esac
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

test('deleteKey removes manual duplicates until 44, then legacy, then managed', async () => {
  await writeFile(join(stubDir, 'manual-DUP_KEY'), '3');
  await writeFile(join(stubDir, 'gui-DUP_KEY'), '');
  await writeFile(join(stubDir, 'managed-DUP_KEY'), '');

  const deleted = await deleteKey('DUP_KEY');
  assert.deepEqual(deleted, ['manual', 'app', 'managed']);
  assert.equal(await exists('manual-DUP_KEY'), false);
  assert.equal(await exists('gui-DUP_KEY'), false);
  assert.equal(await exists('managed-DUP_KEY'), false);

  const calls = (await readFile(callsPath, 'utf8')).trim().split('\n');
  // manual x3 (削除) + manual x1 (44 で終端) → legacy GUI → managed の順
  assert.deepEqual(calls, [
    'DUP_KEY|', 'DUP_KEY|', 'DUP_KEY|', 'DUP_KEY|',
    'com.aieo.aikeychain|DUP_KEY',
    'com.aieo.aikeychain.managed|DUP_KEY',
  ]);
});

test('deleteKey aborts on a legacy failure and leaves the managed copy intact', async () => {
  await writeFile(join(stubDir, 'managed-LEGACY_FAIL_KEY'), '');

  await assert.rejects(() => deleteKey('LEGACY_FAIL_KEY'), /failed to delete/);
  // 権威コピーは無傷（「削除成功」報告後に fallback から復活、を構造的に防ぐ）
  assert.equal(await exists('managed-LEGACY_FAIL_KEY'), true);
  const calls = await readFile(callsPath, 'utf8');
  assert.doesNotMatch(calls, /com\.aieo\.aikeychain\.managed/);
});

test('deleteKey never touches the manual tier for non-env-var-shaped names', async () => {
  // KEY_NAME_PATTERN はドット/小文字を許すが、service="com.vendor.foo" の削除は
  // 無関係アプリのアイテム破壊になる — manual 掃除は厳格名のみ (#179 B4)
  await writeFile(join(stubDir, 'manual-com.vendor.foo'), '1');

  const deleted = await deleteKey('com.vendor.foo');
  assert.deepEqual(deleted, []);
  assert.equal(await exists('manual-com.vendor.foo'), true);
  const calls = (await readFile(callsPath, 'utf8')).trim().split('\n');
  assert.deepEqual(calls, [
    'com.aieo.aikeychain|com.vendor.foo',
    'com.aieo.aikeychain.managed|com.vendor.foo',
  ]);
});

test('deleteKey is idempotent when nothing exists anywhere', async () => {
  const deleted = await deleteKey('NOT_THERE_KEY');
  assert.deepEqual(deleted, []);
});
