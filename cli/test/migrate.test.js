// `akc migrate` (#196): v1 の旧 GUI store / manual スキームを managed へ一括移行。
// stub security で検出・GUI 優先・needs-approval・hex 判別・dry-run・冪等を固定する。
import { test, before, after } from 'node:test';
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

// dump-keychain の内容:
//   managed: EXISTING_KEY（+ 移行で書かれた state ファイル）
//   旧 GUI store: MIG_A / HANG_B(ACL 待ち) / EXISTING_KEY / DUP_K / HEXBIN_E(非印字値)
//                 / HEXLIT_F(値そのものが hex 文字列) / READFAIL_G(read 失敗+stderr に値)
//                 / "bad name!"(v2 名前文法外)
//   manual: MIG_C / DUP_K / AMBIG_M(account 2 種 = #91 重複) / SSH(他アプリ: account がパス)
//   ノイズ: com.apple.NetworkExtension / iCloud / lowercase_svc
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
svc=""; acct=""; w=false; g=false
while [ $# -gt 0 ]; do case "$1" in
  -s) svc="$2"; shift 2 ;; -a) acct="$2"; shift 2 ;; -w) w=true; shift ;; -g) g=true; shift ;; *) shift ;;
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
    emit HEXBIN_E com.aieo.aikeychain
    emit HEXLIT_F com.aieo.aikeychain
    emit READFAIL_G com.aieo.aikeychain
    emit "bad name!" com.aieo.aikeychain
    emit "" com.aieo.aikeychain
    emit "$USER" MIG_C
    emit "$USER" DUP_K
    emit "$USER" AMBIG_M
    emit AMBIG_M AMBIG_M
    emit FALLBACK_H com.aieo.aikeychain
    emit "$USER" FALLBACK_H
    emit DUPAMB_I com.aieo.aikeychain
    emit "$USER" DUPAMB_I
    emit DUPAMB_I DUPAMB_I
    emit FBFAIL_J com.aieo.aikeychain
    emit "$USER" FBFAIL_J
    emit "/Users/x/.ssh/id_ed25519" SSH
    emit account com.apple.NetworkExtension
    emit account iCloud
    emit account lowercase_svc
    exit 0 ;;
  delete-generic-password)
    echo "delete $svc|$acct" >> "$state_dir/deletes.log"; exit 44 ;;
  find-generic-password)
    if [ "$svc" = "com.aieo.aikeychain.managed" ]; then
      [ -e "$state_dir/state-$acct" ] || { echo "could not be found" >&2; exit 44; }
      $w && cat "$state_dir/state-$acct" && echo; exit 0
    fi
    if [ "$svc" = "com.aieo.aikeychain" ]; then
      case "$acct" in
        MIG_A) $w && echo "value-of-MIG_A"; exit 0 ;;
        DUP_K) $w && echo "gui-value-of-DUP_K"; exit 0 ;;
        HEXBIN_E)
          # 非印字値: -w は無印 hex、-g は stderr に password: 0x...
          $w && { echo "6361660ac3a9"; exit 0; }
          $g && { echo 'password: 0x6361660AC3A9  "caf\\né"' >&2; exit 0; }
          exit 0 ;;
        HEXLIT_F)
          # 値そのものが hex 文字列: -g は stderr に password: "..."
          $w && { echo "4142434445464748"; exit 0; }
          $g && { echo 'password: "4142434445464748"' >&2; exit 0; }
          exit 0 ;;
        READFAIL_G)
          echo "diagnostic leaking secret-sentinel-XYZ" >&2; exit 3 ;;
        HANG_B) sleep 60 ;;
        FALLBACK_H) sleep 60 ;;
        DUPAMB_I) sleep 60 ;;
        FBFAIL_J) sleep 60 ;;
        *) echo "could not be found" >&2; exit 44 ;;
      esac
    fi
    case "$svc" in
      MIG_C) $w && echo "value-of-MIG_C"; exit 0 ;;
      DUP_K) $w && echo "manual-value-of-DUP_K"; exit 0 ;;
      AMBIG_M) $w && echo "arbitrary-of-AMBIG_M"; exit 0 ;;
      FALLBACK_H) $w && echo "manual-copy-of-FALLBACK_H"; exit 0 ;;
      DUPAMB_I) $w && echo "arbitrary-of-DUPAMB_I"; exit 0 ;;
      FBFAIL_J) echo "boom secret-sentinel-J" >&2; exit 3 ;;
      SSH) echo "must never be read" >&2; exit 97 ;;
    esac
    echo "could not be found" >&2; exit 44 ;;
  *) echo "stub: unexpected $cmd" >&2; exit 1 ;;
esac
`;

before(async () => {
  stubDir = await mkdtemp(join(tmpdir(), 'akc-migrate-'));
  const stub = join(stubDir, 'security');
  await writeFile(stub, STUB);
  await chmod(stub, 0o755);
  // 初回 exec は Gatekeeper スキャン等で 1 秒超かかることがあり、並列実行時に
  // 短い AIKEYCHAIN_SUBPROCESS_TIMEOUT_MS を食い潰す — ここで一度温めておく。
  await pExecFile(stub, ['dump-keychain']);
});

after(async () => {
  await rm(stubDir, { recursive: true, force: true });
});

const runMigrate = (args) =>
  pExecFile(process.execPath, [AKC, 'migrate', ...args], {
    env: {
      PATH: process.env.PATH,
      USER: process.env.USER,
      AIKEYCHAIN_SECURITY_BIN: join(stubDir, 'security'),
      AIKEYCHAIN_SUBPROCESS_TIMEOUT_MS: '1500',
    },
  }).then(
    (r) => ({ code: 0, ...r }),
    (e) => ({ code: e.code ?? 1, stdout: e.stdout ?? '', stderr: e.stderr ?? '' })
  );

const state = (name) => readFile(join(stubDir, `state-${name}`), 'utf8').catch(() => null);

test('migrate --dry-run prints the plan and writes nothing (#196)', async () => {
  const r = await runMigrate(['--dry-run']);
  // unsupported-name("bad name!") と ambiguous(AMBIG_M) が残るため exit 1（要対応の合図）
  assert.equal(r.code, 1, r.stdout + r.stderr);
  assert.match(r.stdout, /MIG_A/);
  assert.match(r.stdout, /MIG_C/);
  assert.match(r.stdout, /DUP_K.*(dup|duplicate|GUI)/i);
  assert.match(r.stdout, /EXISTING_KEY.*(skip|managed)/i);
  // 旧 v1 が許した名前は黙って落とさず可視化する
  assert.match(r.stdout, /bad name!.*name not supported/);
  // #91 の acct 重複は移行しない
  assert.match(r.stdout, /AMBIG_M.*(ambiguous|multiple|#91)/i);
  // 他アプリの service（大文字でも account がパス）は列挙すらしない
  assert.doesNotMatch(r.stdout, /SSH/);
  assert.doesNotMatch(r.stdout, /NetworkExtension|iCloud|lowercase_svc/);
  assert.equal(await state('MIG_A'), null, 'dry-run must not write');
});

test('migrate --yes: gui+manual, gui wins dups, hex/binary handling, no value leaks (#196)', async () => {
  const r = await runMigrate(['--yes']);
  assert.equal(r.code, 1, r.stdout + r.stderr); // HANG_B(needs-approval) 等が残る
  assert.equal(await state('MIG_A'), 'value-of-MIG_A');
  assert.equal(await state('MIG_C'), 'value-of-MIG_C');
  assert.equal(await state('DUP_K'), 'gui-value-of-DUP_K');
  // 値そのものが hex 文字列 → そのまま移行（hex 推測復号はしない / #179 系）
  assert.equal(await state('HEXLIT_F'), '4142434445464748');
  // 非印字値（-w が hex を出すケース）→ 移行せず unsupported（黙った破損の防止）
  assert.equal(await state('HEXBIN_E'), null);
  assert.match(r.stdout, /HEXBIN_E.*(not printable|non-ASCII|akc set)/);
  // read 失敗は security stderr を転送しない（exit code のみ）
  assert.equal(await state('READFAIL_G'), null);
  assert.match(r.stdout, /READFAIL_G.*read failed \(security exit 3\)/);
  assert.doesNotMatch(r.stdout + r.stderr, /secret-sentinel-XYZ/);
  // ambiguous / 他アプリは書かれない
  assert.equal(await state('AMBIG_M'), null);
  assert.equal(await state('SSH'), null);
  assert.match(r.stdout, /HANG_B/);
  assert.match(r.stdout, /needs-approval/);
  // GUI 側が読めない場合、一意な manual コピーがあればフォールバックで移行する
  assert.equal(await state('FALLBACK_H'), 'manual-copy-of-FALLBACK_H');
  assert.match(r.stdout, /FALLBACK_H.*manual fallback/);
  assert.doesNotMatch(r.stdout, /FALLBACK_H.*(needs-approval|NG)/); // 成功時に矛盾する失敗行を出さない
  // manual 側が #91 の複数 account ならフォールバックに使わない（不定値の混入防止）
  assert.equal(await state('DUPAMB_I'), null);
  assert.match(r.stdout, /DUPAMB_I.*needs-approval/);
  // GUI タイムアウト + fallback 失敗でも needs-approval を失わない（両レビュー N2）
  assert.equal(await state('FBFAIL_J'), null);
  assert.match(r.stdout, /FBFAIL_J.*needs-approval/);
  assert.match(r.stdout, /--interactive --only .*HANG_B/);
  assert.match(r.stdout, /--interactive --only .*FBFAIL_J/);
  assert.doesNotMatch(r.stdout + r.stderr, /secret-sentinel-J/);
  // 生値・エンコード値はどこにも出ない
  assert.doesNotMatch(r.stdout + r.stderr, /value-of-|gui-value|manual-value|arbitrary-of|6361660a|caf\\né/i);
  // 旧アイテムを削除しない
  assert.equal(await readFile(join(stubDir, 'deletes.log'), 'utf8').catch(() => null), null);
});

test('migrate is idempotent: a second full run migrates nothing new (#196)', async () => {
  await rm(join(stubDir, 'state-MIG_A'), { force: true }); // 前テストの状態に依存しない
  const first = await runMigrate(['--yes']);
  assert.notEqual((first.stdout.match(/migrated=(\d+)/) ?? [])[1], '0', first.stdout);
  const second = await runMigrate(['--yes']);
  assert.match(second.stdout, /MIG_A.*(skip|managed)/i);
  assert.match(second.stdout, /MIG_C.*(skip|managed)/i);
  assert.equal((second.stdout.match(/migrated=(\d+)/) ?? [])[1], '0', 'second run must migrate 0 keys');
});

test('migrate --only filters targets (#196)', async () => {
  await rm(join(stubDir, 'state-MIG_A'), { force: true });
  await rm(join(stubDir, 'state-MIG_C'), { force: true });
  const r = await runMigrate(['--yes', '--only', 'MIG_A']);
  assert.equal(r.code, 0, r.stdout + r.stderr);
  assert.equal(await state('MIG_A'), 'value-of-MIG_A');
  assert.equal(await state('MIG_C'), null, '--only で絞ったキー以外は書かない');
});

test('migrate --only with an unmatched name exits 1, not a silent no-op (#196)', async () => {
  const r = await runMigrate(['--yes', '--only', 'TYPO_KEY']);
  assert.equal(r.code, 1);
  assert.match(r.stderr, /TYPO_KEY.*not found/);
});

test('migrate rejects malformed --only values and unknown flags (#196)', async () => {
  for (const args of [['--only'], ['--only', ','], ['--only', '--yes'], ['--frobnicate']]) {
    const r = await runMigrate(args);
    assert.equal(r.code, 1, JSON.stringify(args));
    assert.match(r.stderr, /Usage: akc migrate/);
  }
});

test('migrate without --yes on a non-TTY refuses to write (#196)', async () => {
  await rm(join(stubDir, 'state-MIG_C'), { force: true });
  const r = await runMigrate([]);
  assert.equal(r.code, 1);
  assert.match(r.stderr, /--yes/);
  assert.equal(await state('MIG_C'), null);
});
