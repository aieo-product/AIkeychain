// `akc migrate` (#196) — v1.x のキー（旧 GUI store / manual スキーム）を managed
// namespace へ一括移行する。値はプロセスメモリと pipe のみを通り、argv / env /
// ファイル / stdout / stderr には決して出さない。旧キーは削除しない（読み取りのみ）。
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
 * manual スキーム項目として妥当な account か (#196 レビュー M2)。
 * service 名だけで判定すると `SSH` のような他アプリの大文字 service を誤認し、
 * 無関係なシークレットの読み取り（= 許可ダイアログ誘発）や、prompt-free な
 * managed namespace への複製が起きる。v1 が実際に書いた account の形
 * （空 / $USER / キー名形）に限定する。
 */
function isPlausibleManualAccount(account, user) {
  if (account == null || account === '') return true;
  if (user && account === user) return true;
  return KEY_NAME_PATTERN.test(account);
}

/**
 * dump-keychain の属性レコード（値は含まない）から移行計画を作る純関数。
 * - 旧 GUI store: service=LEGACY_GUI_SERVICE の account
 *   - v2 のキー名文法に合わない account は `unsupported-name`（黙って落とすと
 *     「移行不要」に見える — レビュー指摘）
 * - manual: service が MANUAL_NAME_PATTERN に一致し、かつ全 account が
 *   v1 の書き込み形として妥当なもの。妥当でない account が混じる service は
 *   他アプリ由来とみなし対象外。妥当な account が複数ある service は #91 の
 *   重複事故で、service-only read はどれを返すか不定なので `ambiguous`。
 * - managed に同名があれば skip、GUI/manual 重複は GUI 優先（v1 の解決順）。
 *   GUI 側 entry には manualCopy を立て、GUI 読み取り失敗時のフォールバックに使う。
 */
export function planMigration(records, { user } = {}) {
  const managed = new Set();
  const gui = new Set();
  const guiBadName = new Set();
  const manualAccounts = new Map(); // service -> Set(accounts)
  const manualForeign = new Set(); // 妥当でない account を含む service
  for (const { service, account } of records) {
    if (!service) continue;
    if (service === MANAGED_SERVICE) {
      if (account) managed.add(account);
    } else if (service === LEGACY_GUI_SERVICE) {
      if (!account) continue; // account 無しはキー名として扱えない
      if (KEY_NAME_PATTERN.test(account)) gui.add(account);
      else guiBadName.add(account);
    } else if (MANUAL_NAME_PATTERN.test(service)) {
      if (!isPlausibleManualAccount(account, user)) {
        manualForeign.add(service);
        continue;
      }
      if (!manualAccounts.has(service)) manualAccounts.set(service, new Set());
      manualAccounts.get(service).add(account ?? '');
    }
  }
  const manual = new Set([...manualAccounts.keys()].filter((s) => !manualForeign.has(s)));
  const entries = [];
  for (const name of [...gui].sort()) {
    entries.push({
      name,
      source: 'gui',
      action: managed.has(name) ? 'skip-managed' : 'migrate',
      manualCopy: manual.has(name),
    });
  }
  for (const name of [...guiBadName].sort()) {
    entries.push({ name, source: 'gui', action: 'unsupported-name' });
  }
  for (const name of [...manual].sort()) {
    if (gui.has(name)) {
      entries.push({ name, source: 'manual', action: 'skip-duplicate' });
    } else if (managed.has(name)) {
      entries.push({ name, source: 'manual', action: 'skip-managed' });
    } else if (manualAccounts.get(name).size > 1) {
      entries.push({ name, source: 'manual', action: 'ambiguous' });
    } else {
      entries.push({ name, source: 'manual', action: 'migrate' });
    }
  }
  return entries;
}

const HEX_SHAPED = /^(?:[0-9a-fA-F]{2})+$/;

function securityArgs(name, source, flag) {
  return source === 'gui'
    ? ['find-generic-password', '-s', LEGACY_GUI_SERVICE, '-a', name, flag]
    : ['find-generic-password', '-s', name, flag];
}

async function runSecurity(args, timeoutMs) {
  return pExecFile(SECURITY_BIN, args, {
    maxBuffer: 16 * 1024 * 1024,
    timeout: timeoutMs,
    killSignal: 'SIGKILL',
  });
}

/**
 * 旧位置から値を読む。timeout 超過（= ACL 許可ダイアログ待ち）は 'needs-approval'。
 * 値は返り値のフィールドにのみ載る（出力へは決して流さない）。
 *
 * `find-generic-password -w` は値に非印字/非 ASCII バイトが含まれると **無印の
 * hex** を出力するため、hex 形の出力はそのままでは「hex 文字列そのものが値」と
 * 区別できない（#196 レビュー High: 黙って hex を保存すると成功と報告しつつ値を
 * 壊す）。その場合のみ `-g` を追加実行し、stderr の `password: "…"`（印字可能な
 * 文字列リテラル）か `password: 0x…`（バイナリ）かで判別する。判別できなければ
 * fail-closed で 'unsupported-encoding'。-g の stderr は値を含むため、パース
 * 以外に使わず、いかなる出力にも流さない。
 */
async function readLegacyValue(name, source, timeoutMs) {
  let stdout;
  try {
    ({ stdout } = await runSecurity(securityArgs(name, source, '-w'), timeoutMs));
  } catch (err) {
    if (err.killed === true) return { status: 'needs-approval' };
    if (err.code === 44) return { status: 'not-found' };
    // stderr は値や診断を含み得るため決して転送しない。exit code のみ返す。
    return { status: 'read-failed', code: typeof err.code === 'number' ? err.code : null };
  }
  const value = stdout.endsWith('\n') ? stdout.slice(0, -1) : stdout;
  if (!value) return { status: 'empty' };
  if (!HEX_SHAPED.test(value)) return { status: 'ok', value };
  // hex 形: -g で「リテラル文字列」か「バイナリの hex 表現」かを判別する。
  try {
    const g = await runSecurity(securityArgs(name, source, '-g'), timeoutMs);
    if (/^password: "/m.test(g.stderr)) return { status: 'ok', value }; // 値そのものが hex 文字列
    if (/^password: 0x/m.test(g.stderr)) return { status: 'unsupported-encoding' };
    return { status: 'unsupported-encoding' }; // 判別不能は fail-closed
  } catch {
    return { status: 'unsupported-encoding' };
  }
}

function confirm(question) {
  return new Promise((resolve) => {
    const rl = createInterface({ input: process.stdin, output: process.stderr });
    let settled = false;
    const settle = (v) => {
      if (!settled) {
        settled = true;
        resolve(v);
      }
    };
    // EOF (Ctrl-D) では question のコールバックが呼ばれない — close をキャンセル扱いに。
    rl.on('close', () => settle(false));
    rl.question(question, (answer) => {
      rl.close();
      settle(/^y(es)?$/i.test(answer.trim()));
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
      if (!v || v.startsWith('-')) return { error: '--only requires a comma-separated key list' };
      const names = v.split(',').map((s) => s.trim()).filter(Boolean);
      if (names.length === 0) return { error: '--only requires at least one key name' };
      opts.only = new Set((opts.only ? [...opts.only] : []).concat(names));
    } else return { error: `unknown option: ${a}` };
  }
  return { opts };
}

const PLAN_LABELS = {
  'skip-managed': 'skip — already managed',
  'skip-duplicate': 'skip — duplicate (the GUI store copy is used)',
  'unsupported-name': 'cannot migrate — name not supported by v2 (re-register: akc set)',
  ambiguous: 'cannot migrate — multiple keychain items share this service (#91); re-register: akc set',
};
const planLine = (e) => {
  const label = e.action === 'migrate' ? `migrate (${e.source})` : PLAN_LABELS[e.action];
  return `  ${e.name.padEnd(36)} ${label}`;
};

const FAILURE_TEXT = {
  'not-found': 'old item disappeared',
  empty: 'empty value in the old item',
  'unsupported-encoding':
    'value is not printable single-line ASCII (non-ASCII or multi-line) — re-register with: akc set',
};

export async function cmdMigrate(argv) {
  const { opts, error } = parseArgs(argv);
  if (error) {
    process.stderr.write(
      `akc: ${error}\nUsage: akc migrate [--dry-run] [--yes] [--interactive] [--only KEY,...]\n`
    );
    return 1;
  }
  const out = (s) => process.stdout.write(s);

  let plan = planMigration(await dumpRecords(), { user: process.env.USER });
  let missingOnly = 0;
  if (opts.only) {
    for (const name of opts.only) {
      if (!plan.some((e) => e.name === name)) {
        missingOnly += 1;
        process.stderr.write(`akc: --only ${name}: not found in the migration plan\n`);
      }
    }
    plan = plan.filter((e) => opts.only.has(e.name));
  }
  const targets = plan.filter((e) => e.action === 'migrate');
  const notMigratable = plan.filter(
    (e) => e.action === 'unsupported-name' || e.action === 'ambiguous'
  );

  out(`Migration plan (v1 → managed namespace "${MANAGED_SERVICE}"):\n`);
  for (const e of plan) out(`${planLine(e)}\n`);
  out(
    `Plan: ${targets.length} to migrate, ${plan.length - targets.length - notMigratable.length} skipped` +
      (notMigratable.length ? `, ${notMigratable.length} cannot be migrated (see above)` : '') +
      '.\n'
  );
  out('Old items are never deleted — they stay in the Keychain untouched.\n');

  const attention = notMigratable.length + missingOnly;
  if (opts.dryRun) {
    out('(dry-run) Nothing written.\n');
    return attention > 0 ? 1 : 0;
  }
  if (targets.length === 0) {
    out('Nothing to migrate.\n');
    return attention > 0 ? 1 : 0;
  }
  if (!opts.yes) {
    if (process.stdin.isTTY && process.stderr.isTTY) {
      if (!(await confirm(`Migrate ${targets.length} key(s) now? [y/N] `))) {
        process.stderr.write('akc: cancelled\n');
        return 1;
      }
    } else {
      process.stderr.write(
        'akc: refusing to migrate without confirmation on a non-interactive terminal — re-run with --yes\n'
      );
      return 1;
    }
  }

  const tally = { ok: 0, unsupported: 0, failed: 0 };
  const needsApproval = [];
  const timeoutMs = opts.interactive ? INTERACTIVE_TIMEOUT_MS : SUBPROCESS_TIMEOUT_MS;

  for (const target of targets) {
    const { name } = target;
    // GUI 側の読み取りに失敗しても、manual 側にコピーがあればフォールバックする
    // （#196 レビュー M4: 計画時に GUI 優先で固定すると、読めない GUI 項目の裏に
    // ある読める manual 値へ到達する手段が無くなる）。
    const sources = [target.source, ...(target.manualCopy ? ['manual'] : [])];
    let done = false;
    let sawNeedsApproval = false;
    let lastFailureLine = null;
    for (const source of sources) {
      if (opts.interactive) {
        process.stderr.write(
          `waiting for ${name} (${source}): approve the Keychain dialog ("Always Allow") to continue...\n`
        );
      }
      const r = await readLegacyValue(name, source, timeoutMs);
      if (r.status === 'ok') {
        try {
          await setKey(name, r.value); // printable/長さ/読み戻し検証と redact は setKey 側 (#191/#193)
          const via = source === target.source ? source : `${source} fallback`;
          out(`  ok  ${name.padEnd(36)} migrated (${via})\n`);
          tally.ok += 1;
          done = true;
        } catch (err) {
          if (!(err instanceof KeychainError)) throw err;
          const msg = err.message.split('\n')[0];
          if (/printable ASCII|character limit/.test(msg)) {
            lastFailureLine = `  --  ${name.padEnd(36)} unsupported value: ${msg}\n`;
            tally.unsupported += 1;
            done = true; // 値そのものが対象外 — 別ソースを試しても同じ扱いにしない
          } else {
            lastFailureLine = `  NG  ${name.padEnd(36)} save failed: ${msg}\n`;
            tally.failed += 1;
            done = true;
          }
        }
        break;
      }
      if (r.status === 'needs-approval') {
        sawNeedsApproval = true;
        continue; // 別ソースがあれば試す
      }
      lastFailureLine = `  NG  ${name.padEnd(36)} ${
        r.status === 'read-failed'
          ? `read failed (security exit ${r.code ?? 'unknown'})`
          : FAILURE_TEXT[r.status]
      }\n`;
    }
    if (done) {
      if (lastFailureLine) out(lastFailureLine);
      continue;
    }
    if (sawNeedsApproval) {
      needsApproval.push(name);
      out(`  !!  ${name.padEnd(36)} needs-approval — reading it requires a Keychain permission dialog\n`);
    } else if (lastFailureLine) {
      tally.failed += 1;
      out(lastFailureLine);
    }
  }

  out(
    `Done: migrated=${tally.ok} needs-approval=${needsApproval.length} ` +
      `unsupported=${tally.unsupported} failed=${tally.failed}\n`
  );
  if (needsApproval.length > 0) {
    out(
      'Re-run the remaining keys while answering the Keychain permission dialogs:\n' +
        `  akc migrate --interactive --only ${needsApproval.join(',')}\n`
    );
  }
  return needsApproval.length + tally.unsupported + tally.failed + attention > 0 ? 1 : 0;
}
