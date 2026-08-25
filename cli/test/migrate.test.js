// `akc migrate` (#196): v1 の旧 GUI store / manual スキームを managed へ一括移行。
// stub security で検出・GUI 優先・needs-approval・dry-run・冪等を固定する。
import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdtemp, writeFile, chmod, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const pExecFile = promisify(execFile);
const AKC = join(dirname(fileURLToPath(import.meta.url)), '..', 'bin', 'akc.js');

let stubDir;

// dump-keychain: managed(EXISTING_KEY) + 旧 GUI store(MIG_A / HANG_B / EXISTING_KEY / DUP_K)
// + manual(MIG_C / DUP_K) + ノイズ(com.apple.NetworkExtension, iCloud, lowercase-svc)。
// find: 旧 GUI の HANG_B は sleep で ACL プロンプト待ちを模擬（テストは短い
// AIKEYCHAIN_SUBPROCESS_TIMEOUT_MS で timeout → needs-approval 分類を確認する）。
const STUB = `#!/bin/bash
state_dir="$(cd "$(dirname "$0")" && pwd)"
if [ "$1" = "-i" ]; then
  read -r line
  case "$line" in
    add-generic-password*-s\\ \\"com.aieo.aikeychain.managed\\"*-X\\ *)
      acct=$(printf '%s' "$line" | sed -n 's/.*-a "\\([^"]*\\)".*/\\1/p')
      printf '%s' "\${line##* }" | xxd -r -p > "$state_dir/state-$acct"
      exit 0 ;;
    *) echo "stub -i: unexpected: $line" >&2; exit 1 ;;
  esac
fi
cmd="$1"; shift
svc=""; acct=""; w=false
while [ $# -gt 0 ]; do case "$1" in
  -s) svc="$2"; shift 2 ;; -a) acct="$2"; shift 2 ;; -w) w=true; shift ;; *) shift ;;
esac; done
case "$cmd" in
  dump-keychain)
    emit() { printf 'keychain: "L"\\nclass: "genp"\\nattributes:\\n    "acct"<blob>="%s"\\n    "svce"<blob>="%s"\\n' "$1" "$2"; }
    emit EXISTING_KEY com.aieo.aikeychain.managed
    for f in "$state_dir"/state-*; do
      [ -e "$f" ] || continue
      emit "\${f##*/state-}" com.aieo.aikeychain.managed
    done
    emit MIG_A com.aieo.aikeychain
    emit HANG_B com.aieo.aikeychain
    emit EXISTING_KEY com.aieo.aikeychain
    emit DUP_K com.aieo.aikeychain
    emit "" com.aieo.aikeychain
    emit "$USER" MIG_C
    emit "$USER" DUP_K
    emit account com.apple.NetworkExtension
    emit account iCloud
    emit account lowercase_svc
    exit 0 ;;
  find-generic-password)
    if [ "$svc" = "com.aieo.aikeychain.managed" ]; then
      [ -e "$state_dir/state-$acct" ] || { echo "could not be found" >&2; exit 44; }
      $w && cat "$state_dir/state-$acct" && echo; exit 0
    fi
    if [ "$svc" = "com.aieo.aikeychain" ]; then
      case "$acct" in
        MIG_A) $w && echo "value-of-MIG_A"; exit 0 ;;
        DUP_K) $w && echo "gui-value-of-DUP_K"; exit 0 ;;
        HANG_B) sleep 60 ;;
        *) echo "could not be found" >&2; exit 44 ;;
      esac
    fi
    case "$svc" in
      MIG_C) $w && echo "value-of-MIG_C"; exit 0 ;;
      DUP_K) $w && echo "manual-value-of-DUP_K"; exit 0 ;;
    esac
    echo "could not be found" >&2; exit 44 ;;
  delete-generic-password) exit 44 ;;
  *) echo "stub: unexpected $cmd" >&2; exit 1 ;;
esac
`;

before(async () => {
  stubDir = await mkdtemp(join(tmpdir(), 'akc-migrate-'));
  const stub = join(stubDir, 'security');
  await writeFile(stub, STUB);
  await chmod(stub, 0o755);
});

const runMigrate = (args) =>
  pExecFile(process.execPath, [AKC, 'migrate', ...args], {
    env: {
      PATH: process.env.PATH,
      AIKEYCHAIN_SECURITY_BIN: join(stubDir, 'security'),
      AIKEYCHAIN_SUBPROCESS_TIMEOUT_MS: '1500',
    },
  }).then(
    (r) => ({ code: 0, ...r }),
    (e) => ({ code: e.code ?? 1, stdout: e.stdout ?? '', stderr: e.stderr ?? '' })
  );

test('migrate --dry-run prints the plan and writes nothing (#196)', async () => {
  const r = await runMigrate(['--dry-run']);
  assert.equal(r.code, 0, r.stderr);
  assert.match(r.stdout, /MIG_A/);
  assert.match(r.stdout, /MIG_C/);
  // GUI 優先: manual 側 DUP_K は duplicate skip
  assert.match(r.stdout, /DUP_K.*(dup|duplicate|GUI)/i);
  // managed 済みは skip
  assert.match(r.stdout, /EXISTING_KEY.*(skip|managed)/i);
  // ノイズ service はそもそも出ない
  assert.doesNotMatch(r.stdout, /NetworkExtension|iCloud|lowercase_svc/);
  const written = await readFile(join(stubDir, 'state-MIG_A'), 'utf8').catch(() => null);
  assert.equal(written, null, 'dry-run must not write');
});

test('migrate --yes migrates gui+manual, gui wins duplicates, hang -> needs-approval (#196)', async () => {
  const r = await runMigrate(['--yes']);
  // needs-approval が残るので exit 1（未完了の合図）
  assert.equal(r.code, 1, r.stdout + r.stderr);
  assert.equal(await readFile(join(stubDir, 'state-MIG_A'), 'utf8'), 'value-of-MIG_A');
  assert.equal(await readFile(join(stubDir, 'state-MIG_C'), 'utf8'), 'value-of-MIG_C');
  assert.equal(await readFile(join(stubDir, 'state-DUP_K'), 'utf8'), 'gui-value-of-DUP_K');
  assert.match(r.stdout, /HANG_B/);
  assert.match(r.stdout, /needs-approval|許可/);
  assert.match(r.stdout, /--interactive --only HANG_B/);
  // 値・hex はどこにも出ない
  assert.doesNotMatch(r.stdout + r.stderr, /value-of-|gui-value|manual-value|76616c/);
});

test('migrate is idempotent: second run skips everything migrated (#196)', async () => {
  const r = await runMigrate(['--yes']);
  assert.match(r.stdout, /MIG_A.*(skip|managed)/i);
  assert.match(r.stdout, /MIG_C.*(skip|managed)/i);
});

test('migrate --only filters targets (#196)', async () => {
  await rm(join(stubDir, 'state-MIG_A'), { force: true });
  await rm(join(stubDir, 'state-MIG_C'), { force: true });
  const r = await runMigrate(['--yes', '--only', 'MIG_A']);
  assert.equal(r.code, 0, r.stdout + r.stderr);
  assert.equal(await readFile(join(stubDir, 'state-MIG_A'), 'utf8'), 'value-of-MIG_A');
  const c = await readFile(join(stubDir, 'state-MIG_C'), 'utf8').catch(() => null);
  assert.equal(c, null, '--only で絞ったキー以外は書かない');
});

test('migrate without --yes on a non-TTY refuses to write (#196)', async () => {
  await rm(join(stubDir, 'state-MIG_C'), { force: true });
  const r = await runMigrate([]);
  assert.equal(r.code, 1);
  assert.match(r.stderr, /--yes/);
  const c = await readFile(join(stubDir, 'state-MIG_C'), 'utf8').catch(() => null);
  assert.equal(c, null);
});
