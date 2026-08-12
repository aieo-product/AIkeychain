// Thin wrapper around the macOS `security` CLI.
// Lookup order matches scripts/akc (issue #91):
//   1. service="com.aieo.aikeychain" account="<KEY>"  (AI KeyChain GUI store)
//   2. service="<KEY>" with NO account               (only when GUI exits 44/not-found)
// Manual keys are looked up by service only because their `acct` attribute is
// not consistent ($USER or the service name) — pinning -a can grab a stale
// duplicate entry and return an invalid value.

import { execFile, spawn } from 'node:child_process';
import { promisify } from 'node:util';
import { isAbsolute } from 'node:path';

const pExecFile = promisify(execFile);

// Always invoke the `security` binary by absolute path (issue #117): a bare
// 'security' command name is resolved via PATH lookup, so a same-uid
// attacker (or a malicious postinstall from any other npm package) could
// place a fake `security` earlier on PATH and intercept secrets — including
// the hex-encoded value fed to `add-generic-password` on stdin — without the
// real Keychain's ACL/authorization prompt ever appearing. The Swift GUI
// already hardcodes /usr/bin/security; the CLI must match.
//
// AIKEYCHAIN_SECURITY_BIN is an override for tests only (to point at a PATH
// stub instead of the real binary) — it must never be relied on in
// production, where the default below is always used.
//
// The override MUST be an absolute path. A relative value (e.g. "security")
// would fall back to PATH lookup inside execFile/spawn and silently
// reintroduce the very #117 vulnerability this fix closes, so a non-absolute
// override is ignored in favor of the hardcoded default.
const securityBinOverride = process.env.AIKEYCHAIN_SECURITY_BIN;
export const SECURITY_BIN =
  securityBinOverride && isAbsolute(securityBinOverride)
    ? securityBinOverride
    : '/usr/bin/security';

export const KEY_NAME_PATTERN = /^[A-Za-z0-9_.-]+$/;

export const GUI_SERVICE = 'com.aieo.aikeychain';
// Manual entries are identified by env-var-shaped service names (e.g. GITHUB_TOKEN).
export const MANUAL_NAME_PATTERN = /^[A-Z][A-Z0-9_]*$/;

export class KeychainError extends Error {}

export function assertMacOS() {
  if (process.platform !== 'darwin') {
    throw new KeychainError(
      'aikeychain requires macOS: secrets are stored in the macOS Keychain via the `security` command.'
    );
  }
}

async function security(args) {
  try {
    const { stdout, stderr } = await pExecFile(SECURITY_BIN, args, {
      maxBuffer: 16 * 1024 * 1024,
    });
    return { ok: true, code: 0, stdout, stderr };
  } catch (err) {
    return {
      ok: false,
      code: err.code ?? null,
      stdout: err.stdout ?? '',
      stderr: err.stderr ?? String(err),
    };
  }
}

function stripTrailingNewline(s) {
  return s.endsWith('\n') ? s.slice(0, -1) : s;
}

/** Resolve a key to its secret value, or null if not found. */
export async function resolveKey(name) {
  const gui = await security(['find-generic-password', '-s', GUI_SERVICE, '-a', name, '-w']);
  if (gui.ok) {
    const value = stripTrailingNewline(gui.stdout);
    return value || null;
  }
  if (gui.code !== 44) return null;

  const manual = await security(['find-generic-password', '-s', name, '-w']);
  if (manual.ok) {
    const value = stripTrailingNewline(manual.stdout);
    if (value) return value;
  }
  return null;
}

/** Check where a key exists without reading its secret value. */
export async function keyExists(name) {
  const app = (await security(['find-generic-password', '-s', GUI_SERVICE, '-a', name])).ok;
  const manual = (await security(['find-generic-password', '-s', name])).ok;
  return { name, app, manual, exists: app || manual };
}

/** Redact hex-encoded secret material from text destined for errors/logs. */
export function redactSecrets(text) {
  return text.replace(/-X\s+[0-9a-fA-F]+/g, '-X <redacted>');
}

/** Run a command through `security -i`, which reads commands from stdin. */
function securityInteractive(commandLine) {
  return new Promise((resolve) => {
    const child = spawn(SECURITY_BIN, ['-i'], { stdio: ['pipe', 'pipe', 'pipe'] });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (chunk) => (stdout += chunk));
    child.stderr.on('data', (chunk) => (stderr += chunk));
    child.on('error', (err) => resolve({ ok: false, stdout, stderr: String(err) }));
    child.on('close', (code) => resolve({ ok: code === 0, stdout, stderr }));
    child.stdin.write(`${commandLine}\n`);
    child.stdin.end();
  });
}

/**
 * Store a key. Defaults to the AI KeyChain GUI store so the entry shows up in
 * the app. `-U` updates in place to avoid acct-mismatched duplicates.
 *
 * The secret never appears in any process's argv (issue #94): the command is
 * fed to `security -i` via stdin, and the value is hex-encoded with -X so no
 * quoting of the interactive command line is needed.
 */
export async function setKey(name, value, { manual = false } = {}) {
  if (!name) throw new KeychainError('key name is required');
  if (!KEY_NAME_PATTERN.test(name)) {
    throw new KeychainError('key name must match [A-Za-z0-9_.-]+');
  }
  if (!value) throw new KeychainError('refusing to store an empty value');
  // Control characters would store fine but `find-generic-password -w` falls
  // back to hex output for them, breaking round-trips — reject up front.
  // eslint-disable-next-line no-control-regex
  if (/[\u0000-\u001f\u007f]/.test(value)) {
    throw new KeychainError('value must not contain control characters (newlines, tabs, NUL)');
  }
  const service = manual ? name : GUI_SERVICE;
  const hex = Buffer.from(value, 'utf8').toString('hex');
  // -T: 作成時に GUI アプリと security CLI を Keychain ACL の信頼リストへ登録する
  // (issue #162)。これが無いと GUI からの読み取りがアイテムごとに承認ダイアログを
  // 出す。-T は作成時のみ有効で、-U による既存アイテム更新では ACL は変わらない。
  // パスのアプリが存在しない環境でも add 自体は成功する。
  const r = await securityInteractive(
    `add-generic-password -U -s "${service}" -a "${name}" ` +
      `-T "/Applications/AI KeyChain.app" -T "/usr/bin/security" -X ${hex}`
  );
  if (!r.ok) {
    // `security -i` stderr could in principle echo the command line (which
    // carries the hex value) — redact before it reaches CLI stderr / MCP.
    throw new KeychainError(`failed to save "${name}": ${redactSecrets(r.stderr.trim()) || 'unknown error'}`);
  }
  // Read-back verification against the exact target item: -U can report
  // success in odd keychain states while leaving a stale value behind.
  // (`find -w` prints hex for non-ASCII payloads, so accept that form too.)
  const readBack = await security(['find-generic-password', '-s', service, '-a', name, '-w']);
  const got = readBack.ok ? stripTrailingNewline(readBack.stdout) : null;
  if (got !== value && got?.toLowerCase() !== hex) {
    throw new KeychainError(
      `save reported success but reading "${name}" back returned a different value — check Keychain state`
    );
  }
  return { service, account: name };
}

/** Delete a key from the GUI store and/or the manual store. Returns which stores were deleted. */
export async function deleteKey(name, { app = true, manual = true } = {}) {
  const deleted = [];
  if (app) {
    const r = await security(['delete-generic-password', '-s', GUI_SERVICE, '-a', name]);
    if (r.ok) deleted.push('app');
  }
  if (manual) {
    const r = await security(['delete-generic-password', '-s', name]);
    if (r.ok) deleted.push('manual');
  }
  return deleted;
}

/** Parse `security dump-keychain` output into { service, account } records. */
export function parseDump(dump) {
  const records = [];
  for (const block of dump.split(/^keychain: /m)) {
    if (!/^class: "genp"/m.test(block)) continue;
    const svce = block.match(/"svce"<blob>="([^"\n]*)"/);
    const acct = block.match(/"acct"<blob>="([^"\n]*)"/);
    records.push({ service: svce ? svce[1] : null, account: acct ? acct[1] : null });
  }
  return records;
}

/**
 * List known keys (names only — secret values are never read).
 * Returns [{ name, sources: ['app'|'manual', ...] }] sorted by name.
 */
export async function listKeys() {
  const r = await security(['dump-keychain']);
  if (!r.ok) {
    throw new KeychainError(`failed to enumerate keychain items: ${r.stderr.trim()}`);
  }
  const keys = new Map();
  const add = (name, source) => {
    if (!keys.has(name)) keys.set(name, new Set());
    keys.get(name).add(source);
  };
  for (const { service, account } of parseDump(r.stdout)) {
    if (service === GUI_SERVICE && account) {
      add(account, 'app');
    } else if (service && service !== GUI_SERVICE && MANUAL_NAME_PATTERN.test(service)) {
      add(service, 'manual');
    }
  }
  return [...keys.entries()]
    .map(([name, sources]) => ({ name, sources: [...sources].sort() }))
    .sort((a, b) => a.name.localeCompare(b.name));
}

/**
 * Detect ambiguous duplicate entries: env-var-shaped service names that have
 * more than one generic-password item with distinct `acct` values. For such a
 * service, `security find-generic-password -s NAME -w` returns an unspecified
 * one of them — the root cause of issue #91 ("registered but invalid token").
 *
 * Secret values are never read; only the `acct` attribute (from dump-keychain)
 * is reported so the user can identify and remove the stale entry.
 *
 * Returns [{ service, accounts: [...] }] sorted by service, accounts sorted.
 */
export function findAmbiguousDuplicates(records) {
  const byService = new Map();
  for (const { service, account } of records) {
    if (!service || service === GUI_SERVICE) continue;
    if (!MANUAL_NAME_PATTERN.test(service)) continue;
    if (!byService.has(service)) byService.set(service, new Set());
    byService.get(service).add(account ?? '');
  }
  return [...byService.entries()]
    .filter(([, accts]) => accts.size > 1)
    .map(([service, accts]) => ({ service, accounts: [...accts].sort() }))
    .sort((a, b) => a.service.localeCompare(b.service));
}

/** Convenience wrapper around the live keychain dump (names/accts only). */
export async function listAmbiguousDuplicates() {
  const r = await security(['dump-keychain']);
  if (!r.ok) {
    throw new KeychainError(`failed to enumerate keychain items: ${r.stderr.trim()}`);
  }
  return findAmbiguousDuplicates(parseDump(r.stdout));
}

// 固定長マスク。桁数（value.length）は出さない: 正確な長さは総当たりコストを
// 下げる・キー種別/世代を識別できるメタデータで、端末スクロールバックや
// エビデンスキャプチャに残る（scripts/akc は #115/#123 で対応済み。CLI 側も統一）。
export function maskValue(_value) {
  return '********';
}
