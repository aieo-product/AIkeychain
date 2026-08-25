// `akc migrate` (#196) — v1.x のキー（旧 GUI store / manual スキーム）を managed
// namespace へ一括移行する。値はプロセスメモリと pipe のみを通り、argv / env /
// ファイル / 端末には決して出さない。旧キーは削除しない（読み取りのみ）。
//
// v2.0 で keychain.js は「managed のみ」に絞られたため、レガシー読み取りは
// このモジュールに閉じ込める（migrate が唯一の正当なレガシー消費者）。

import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { createInterface } from 'node:readline';
import {
  dumpRecords,
  setKey,
  KeychainError,
  MANAGED_SERVICE,
  SECURITY_BIN,
  SUBPROCESS_TIMEOUT_MS,
  KEY_NAME_PATTERN,
} from './keychain.js';

const pExecFile = promisify(execFile);

/** v1.x の GUI store service 名（v2 は読まない・migrate だけが参照する）。 */
export const LEGACY_GUI_SERVICE = 'com.aieo.aikeychain';

// v1 の manual スキーム判定と同一の厳格パターン（#160/#163、GUI/CLI 共通規則）:
// 大文字スネークケース限定。緩くすると iCloud / com.apple.* 等のシステム項目を
// 「キー」と誤認して無関係なアイテムへ read が波及するため、ここは広げない。
export const MANUAL_NAME_PATTERN = /^[A-Z][A-Z0-9_]*$/;

// --interactive での 1 キーあたりの許可ダイアログ待ち上限。
const INTERACTIVE_TIMEOUT_MS = 600_000;

/**
 * dump-keychain の属性レコード（値は含まない）から移行計画を作る純関数。
 * - 旧 GUI store: service=LEGACY_GUI_SERVICE の account（akc set 可能な名前のみ）
 * - manual: service が MANUAL_NAME_PATTERN に一致
 * - managed に同名があれば skip、GUI/manual 重複は GUI 優先（v1 の解決順と同じ）
 */
export function planMigration(records) {
  const managed = new Set();
  const gui = new Set();
  const manual = new Set();
  for (const { service, account } of records) {
    if (!service) continue;
    if (service === MANAGED_SERVICE) {
      if (account) managed.add(account);
    } else if (service === LEGACY_GUI_SERVICE) {
      if (account && KEY_NAME_PATTERN.test(account)) gui.add(account);
    } else if (MANUAL_NAME_PATTERN.test(service)) {
      manual.add(service);
    }
  }
  const entries = [];
  for (const name of [...gui].sort()) {
    entries.push({ name, source: 'gui', action: managed.has(name) ? 'skip-managed' : 'migrate' });
  }
  for (const name of [...manual].sort()) {
    if (gui.has(name)) {
      entries.push({ name, source: 'manual', action: 'skip-duplicate' });
    } else {
      entries.push({ name, source: 'manual', action: managed.has(name) ? 'skip-managed' : 'migrate' });
    }
  }
  return entries;
}

/**
 * 旧位置から値を読む。timeout 超過（= ACL 許可ダイアログ待ち）は 'needs-approval'。
 * 値は返り値のフィールドにのみ載る（ログ等へは出さない）。
 */
async function readLegacyValue(name, source, timeoutMs) {
  const args =
    source === 'gui'
      ? ['find-generic-password', '-s', LEGACY_GUI_SERVICE, '-a', name, '-w']
      : ['find-generic-password', '-s', name, '-w'];
  try {
    const { stdout } = await pExecFile(SECURITY_BIN, args, {
      maxBuffer: 16 * 1024 * 1024,
      timeout: timeoutMs,
      killSignal: 'SIGKILL',
    });
    const value = stdout.endsWith('\n') ? stdout.slice(0, -1) : stdout;
    return value ? { status: 'ok', value } : { status: 'empty' };
  } catch (err) {
    if (err.killed === true) return { status: 'needs-approval' };
    if (err.code === 44) return { status: 'not-found' };
    return { status: 'read-failed', detail: (err.stderr ?? String(err)).trim().split('\n')[0] };
  }
}

function confirm(question) {
  return new Promise((resolve) => {
    const rl = createInterface({ input: process.stdin, output: process.stderr });
    rl.question(question, (answer) => {
      rl.close();
      resolve(/^y(es)?$/i.test(answer.trim()));
    });
  });
}

function parseArgs(argv) {
  const opts = { dryRun: false, yes: false, interactive: false, only: null };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--dry-run') opts.dryRun = true;
    else if (a === '--yes') opts.yes = true;
    else if (a === '--interactive') opts.interactive = true;
    else if (a === '--only') {
      const v = argv[++i];
      if (!v) return { error: '--only requires a comma-separated key list' };
      opts.only = new Set((opts.only ? [...opts.only] : []).concat(v.split(',').map((s) => s.trim()).filter(Boolean)));
    } else return { error: `unknown option: ${a}` };
  }
  return { opts };
}

const planLine = (e) => {
  const label =
    e.action === 'migrate'
      ? `migrate (${e.source})`
      : e.action === 'skip-managed'
        ? 'skip — already managed'
        : 'skip — duplicate (GUI store version wins)';
  return `  ${e.name.padEnd(36)} ${label}`;
};

export async function cmdMigrate(argv) {
  const { opts, error } = parseArgs(argv);
  if (error) {
    process.stderr.write(`akc: ${error}\nUsage: akc migrate [--dry-run] [--yes] [--interactive] [--only KEY,...]\n`);
    return 1;
  }
  const out = (s) => process.stdout.write(s);

  let plan = planMigration(await dumpRecords());
  if (opts.only) {
    for (const name of opts.only) {
      if (!plan.some((e) => e.name === name)) {
        process.stderr.write(`akc: --only ${name}: not found in the migration plan (ignored)\n`);
      }
    }
    plan = plan.filter((e) => opts.only.has(e.name));
  }
  const targets = plan.filter((e) => e.action === 'migrate');

  out(`Migration plan (v1 → managed namespace "${MANAGED_SERVICE}"):\n`);
  for (const e of plan) out(`${planLine(e)}\n`);
  out(`Plan: ${targets.length} to migrate, ${plan.length - targets.length} skipped.\n`);
  out('Old items are never deleted — they stay in the Keychain untouched.\n');

  if (opts.dryRun) {
    out('(dry-run) Nothing written.\n');
    return 0;
  }
  if (targets.length === 0) {
    out('Nothing to migrate.\n');
    return 0;
  }
  if (!opts.yes) {
    if (process.stdin.isTTY && process.stderr.isTTY) {
      if (!(await confirm(`Migrate ${targets.length} key(s) now? [y/N] `))) {
        process.stderr.write('akc: cancelled\n');
        return 1;
      }
    } else {
      process.stderr.write('akc: refusing to migrate without confirmation on a non-interactive terminal — re-run with --yes\n');
      return 1;
    }
  }

  const tally = { ok: 0, unsupported: 0, failed: 0 };
  const needsApproval = [];
  for (const { name, source } of targets) {
    if (opts.interactive) {
      process.stderr.write(`⏳ ${name}: Keychain の許可ダイアログが出たら「常に許可」を選んでください…\n`);
    }
    const r = await readLegacyValue(name, source, opts.interactive ? INTERACTIVE_TIMEOUT_MS : SUBPROCESS_TIMEOUT_MS);
    if (r.status === 'needs-approval') {
      needsApproval.push(name);
      out(`  ⚠️  ${name.padEnd(36)} needs-approval — 読み取りに Keychain の許可が必要です\n`);
      continue;
    }
    if (r.status === 'not-found' || r.status === 'empty') {
      tally.failed += 1;
      out(`  ✖  ${name.padEnd(36)} ${r.status === 'empty' ? 'empty value in the old item' : 'old item disappeared'}\n`);
      continue;
    }
    if (r.status === 'read-failed') {
      tally.failed += 1;
      out(`  ✖  ${name.padEnd(36)} read failed: ${r.detail || 'unknown error'}\n`);
      continue;
    }
    try {
      await setKey(name, r.value); // 検証（printable/長さ/読み戻し）と redact は setKey 側 (#191/#193)
      tally.ok += 1;
      out(`  ✅ ${name.padEnd(36)} migrated (${source})\n`);
    } catch (err) {
      if (!(err instanceof KeychainError)) throw err;
      const msg = err.message.split('\n')[0];
      if (/printable ASCII|character limit/.test(msg)) {
        tally.unsupported += 1;
        out(`  ✖  ${name.padEnd(36)} unsupported value: ${msg}\n`);
      } else {
        tally.failed += 1;
        out(`  ✖  ${name.padEnd(36)} save failed: ${msg}\n`);
      }
    }
  }

  out(
    `Done: migrated=${tally.ok} needs-approval=${needsApproval.length} ` +
      `unsupported=${tally.unsupported} failed=${tally.failed}\n`
  );
  if (needsApproval.length > 0) {
    out(
      '次のコマンドで、許可ダイアログに応答しながら残りを移行できます:\n' +
        `  akc migrate --interactive --only ${needsApproval.join(',')}\n`
    );
  }
  return needsApproval.length + tally.unsupported + tally.failed > 0 ? 1 : 0;
}
