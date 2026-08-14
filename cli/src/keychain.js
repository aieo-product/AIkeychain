// Thin wrapper around the macOS `security` CLI.
// Lookup order matches scripts/akc (issues #91, #167):
//   1. service="com.aieo.aikeychain.managed" account="<KEY>"  (managed namespace, v1.9+)
//   2. service="com.aieo.aikeychain" account="<KEY>"          (legacy GUI store)
//   3. service="<KEY>" with NO account                        (legacy manual scheme)
// Each tier falls through ONLY on exit 44 (not found) — any other failure is
// authoritative and fails closed (#147/#150 semantics).
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
// v1.9+ managed namespace (#167): every key under it was created by
// /usr/bin/security, so headless reads never prompt. New writes go here;
// GUI_SERVICE and the manual scheme remain read-only legacy fallbacks.
export const MANAGED_SERVICE = 'com.aieo.aikeychain.managed';
// Manual entries are identified by env-var-shaped service names (e.g. GITHUB_TOKEN).
export const MANUAL_NAME_PATTERN = /^[A-Z][A-Z0-9_]*$/;

export class KeychainError extends Error {}

/**
 * A legacy (GUI-owned or manual) item blocked the headless read on a keychain
 * consent prompt and the subprocess was killed (#171). The contract is
 * "new/migrated (managed) keys succeed silently; legacy keys fail bounded" —
 * NOT "mixed stores always succeed". The fix is migration, so say so.
 */
export class MigrationRequiredError extends KeychainError {
  constructor(name, store) {
    super(
      `"${name}" is stored as a legacy ${store} item that cannot be read headlessly ` +
        `(the read blocked on a keychain prompt and was killed after ${SUBPROCESS_TIMEOUT_MS / 1000}s). ` +
        `Migrate it to the managed namespace: re-register with \`akc set ${name}\`, ` +
        `or use the AI KeyChain app's migration assistant.`
    );
    this.keyName = name;
    this.store = store;
  }
}

export function assertMacOS() {
  if (process.platform !== 'darwin') {
    throw new KeychainError(
      'aikeychain requires macOS: secrets are stored in the macOS Keychain via the `security` command.'
    );
  }
}

// Bound every subprocess: a prompt-blocked keychain operation must fail after
// SUBPROCESS_TIMEOUT_MS instead of hanging `akc run`/`akc set` forever — the
// whole point of the headless epic (#167/#171). Matches the Swift service's
// timeout + SIGKILL semantics.
//
// AIKEYCHAIN_SUBPROCESS_TIMEOUT_MS is a test-only override (so the hang path
// can be exercised without waiting 10s). Production always uses the default.
const timeoutOverride = Number(process.env.AIKEYCHAIN_SUBPROCESS_TIMEOUT_MS);
export const SUBPROCESS_TIMEOUT_MS =
  Number.isFinite(timeoutOverride) && timeoutOverride > 0 ? timeoutOverride : 10_000;

async function security(args) {
  try {
    const { stdout, stderr } = await pExecFile(SECURITY_BIN, args, {
      maxBuffer: 16 * 1024 * 1024,
      timeout: SUBPROCESS_TIMEOUT_MS,
      killSignal: 'SIGKILL',
    });
    return { ok: true, code: 0, stdout, stderr };
  } catch (err) {
    return {
      ok: false,
      code: err.code ?? null,
      // execFile sets killed=true when OUR timeout fired and we sent the kill
      // signal — the marker for "the read blocked (keychain prompt) and was
      // killed", which callers turn into a bounded, explanatory error (#171).
      timedOut: err.killed === true,
      stdout: err.stdout ?? '',
      stderr: err.stderr ?? String(err),
    };
  }
}

function stripTrailingNewline(s) {
  return s.endsWith('\n') ? s.slice(0, -1) : s;
}

/**
 * Resolve a key to its secret value, or null if not found.
 * Throws MigrationRequiredError when a legacy tier blocks on a prompt (#171),
 * and KeychainError when the managed tier times out (managed items are
 * security-owned and never prompt — a timeout there means a locked/unavailable
 * keychain, not an ownership problem).
 */
export async function resolveKey(name) {
  // Lookup order: managed (v1.9+, always headless-readable) -> legacy GUI -> manual.
  const managed = await security(['find-generic-password', '-s', MANAGED_SERVICE, '-a', name, '-w']);
  if (managed.ok) {
    const value = stripTrailingNewline(managed.stdout);
    return value || null;
  }
  if (managed.timedOut) {
    throw new KeychainError(
      `reading "${name}" from the managed namespace timed out — the keychain is likely locked ` +
        'or unavailable. Unlock the login keychain and retry.'
    );
  }
  if (managed.code !== 44) return null; // fail closed on unexpected errors (#147 semantics)
  const gui = await security(['find-generic-password', '-s', GUI_SERVICE, '-a', name, '-w']);
  if (gui.ok) {
    const value = stripTrailingNewline(gui.stdout);
    return value || null;
  }
  if (gui.timedOut) throw new MigrationRequiredError(name, 'GUI-store');
  if (gui.code !== 44) return null;

  const manual = await security(['find-generic-password', '-s', name, '-w']);
  if (manual.ok) {
    const value = stripTrailingNewline(manual.stdout);
    if (value) return value;
  }
  if (manual.timedOut) throw new MigrationRequiredError(name, 'manual');
  return null;
}

/**
 * Check where a key exists without reading its secret value.
 * Fails closed (#150 semantics, same as resolveKey): only exit 44 means
 * "not in this store" — any other failure throws instead of being silently
 * treated as absent, so `akc check`/`akc get` never report a key as usable
 * (or missing) based on a store we could not actually query.
 */
export async function keyExists(name) {
  const probe = async (args) => {
    const r = await security(args);
    if (r.ok) return true;
    if (r.code === 44) return false;
    throw new KeychainError(
      `keychain probe failed (exit ${r.code}): ${r.stderr.trim() || 'unknown error'}`
    );
  };
  const managed = await probe(['find-generic-password', '-s', MANAGED_SERVICE, '-a', name]);
  const app = await probe(['find-generic-password', '-s', GUI_SERVICE, '-a', name]);
  const manual = await probe(['find-generic-password', '-s', name]);
  return { name, managed, app, manual, exists: managed || app || manual };
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
    let settled = false;
    const settle = (result) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve(result);
    };
    // Same bound as security(): a prompt-blocked write must fail, not hang (#167).
    const timer = setTimeout(() => {
      child.kill('SIGKILL');
      settle({ ok: false, stdout, stderr: 'security -i timed out (prompt-blocked?)' });
    }, SUBPROCESS_TIMEOUT_MS);
    child.stdout.on('data', (chunk) => (stdout += chunk));
    child.stderr.on('data', (chunk) => (stderr += chunk));
    child.on('error', (err) => settle({ ok: false, stdout, stderr: String(err) }));
    child.on('close', (code) => settle({ ok: code === 0, stdout, stderr }));
    child.stdin.write(`${commandLine}\n`);
    child.stdin.end();
  });
}

// Maximum value length, matching the Swift service (SecurityCLIKeychainService
// .maxValueLength): keeps the whole `security -i` command within the 64KB pipe
// buffer after hex expansion, so the stdin write can never deadlock.
export const MAX_VALUE_LENGTH = 8192;

/**
 * Store a key in the managed namespace (#167) — the single write target for
 * both CLI and GUI. `-U` updates in place to avoid acct-mismatched duplicates
 * (safe for headless reads even on security-owned items, spike S7').
 *
 * The secret never appears in any process's argv (issue #94): the command is
 * fed to `security -i` via stdin, and the value is hex-encoded with -X so no
 * quoting of the interactive command line is needed.
 */
export async function setKey(name, value) {
  if (!name) throw new KeychainError('key name is required');
  if (!KEY_NAME_PATTERN.test(name)) {
    throw new KeychainError('key name must match [A-Za-z0-9_.-]+');
  }
  if (!value) throw new KeychainError('refusing to store an empty value');
  // Printable ASCII only, matching the Swift service: `find-generic-password
  // -w` prints hex for any value containing a non-printable byte, and guessing
  // "looks like hex -> decode it" corrupts legitimate all-hex secrets (#179
  // review). Restrict the write side so the read side is always raw.
  // Non-ASCII/multi-line support is deferred to the C7 (#174) encoding convention.
  if (!/^[\x20-\x7e]+$/.test(value)) {
    throw new KeychainError(
      'value must be printable ASCII (no newlines, tabs, control or non-ASCII characters) — non-ASCII/multi-line values are not supported yet'
    );
  }
  if (value.length > MAX_VALUE_LENGTH) {
    throw new KeychainError(`value exceeds the ${MAX_VALUE_LENGTH}-character limit`);
  }
  // All writes target the managed namespace (#167). The legacy manual scheme
  // is no longer a write target (the old --manual path could create
  // acct-mismatched duplicates — the exact #91 failure mode).
  const service = MANAGED_SERVICE;
  const hex = Buffer.from(value, 'utf8').toString('hex');
  const r = await securityInteractive(
    `add-generic-password -U -s "${service}" -a "${name}" -X ${hex}`
  );
  if (!r.ok) {
    // `security -i` stderr could in principle echo the command line (which
    // carries the hex value) — redact before it reaches CLI stderr / MCP.
    throw new KeychainError(`failed to save "${name}": ${redactSecrets(r.stderr.trim()) || 'unknown error'}`);
  }
  // Read-back verification against the exact target item: -U can report
  // success in odd keychain states while leaving a stale value behind.
  // Values are printable ASCII (enforced above), so `find -w` always prints
  // them raw — a hex-shaped readback is a real mismatch, not an encoding.
  const readBack = await security(['find-generic-password', '-s', service, '-a', name, '-w']);
  const got = readBack.ok ? stripTrailingNewline(readBack.stdout) : null;
  if (got !== value) {
    throw new KeychainError(
      `save reported success but reading "${name}" back returned a different value — check Keychain state`
    );
  }
  return { service, account: name };
}

/**
 * Delete a key from every store it lives in. Returns which stores were deleted.
 *
 * Order matters (#179 review): fallback stores (manual -> legacy GUI) are
 * cleaned up BEFORE the authoritative managed copy. If a fallback delete
 * fails, we throw with the managed copy intact — the key still resolves and
 * the user sees the failure, instead of "deleted" being reported while a
 * stale fallback copy keeps resolving. Exit 44 (not found) is the only benign
 * failure; anything else throws.
 */
export async function deleteKey(name) {
  const deleted = [];
  const del = async (args) => {
    const r = await security(args);
    if (r.ok) return true;
    if (r.code === 44) return false;
    throw new KeychainError(
      `failed to delete "${name}" (exit ${r.code}): ${r.stderr.trim() || 'unknown error'}`
    );
  };

  // Manual scheme: strict env-var-shaped names only — KEY_NAME_PATTERN also
  // allows dots/lowercase, and deleting service="com.vendor.foo" would remove
  // an unrelated app's item. `delete-generic-password -s NAME` removes only
  // the first match, so loop until exit 44 to clear duplicates (#100).
  if (MANUAL_NAME_PATTERN.test(name)) {
    let removedAny = false;
    for (let i = 0; i < 10; i++) {
      if (!(await del(['delete-generic-password', '-s', name]))) break;
      removedAny = true;
    }
    if (removedAny) deleted.push('manual');
  }
  if (await del(['delete-generic-password', '-s', GUI_SERVICE, '-a', name])) {
    deleted.push('app');
  }
  if (await del(['delete-generic-password', '-s', MANAGED_SERVICE, '-a', name])) {
    deleted.push('managed');
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
    if (service === MANAGED_SERVICE && account) {
      add(account, 'app');
    } else if (service === GUI_SERVICE && account) {
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
    if (!service || service === GUI_SERVICE || service === MANAGED_SERVICE) continue;
    if (!MANUAL_NAME_PATTERN.test(service)) continue;
    if (!byService.has(service)) byService.set(service, new Set());
    byService.get(service).add(account ?? '');
  }
  return [...byService.entries()]
    .filter(([, accts]) => accts.size > 1)
    .map(([service, accts]) => ({ service, accounts: [...accts].sort() }))
    .sort((a, b) => a.service.localeCompare(b.service));
}

/**
 * Detect keys that exist only in legacy namespaces (GUI store / manual scheme)
 * with no managed copy (#171). These are exactly the keys whose headless reads
 * can prompt/hang; the doctor surfaces them with migration guidance.
 * Non-destructive: derived from dump-keychain attributes — no values are read
 * and no `find -w` probes run (a probe would rain consent dialogs when headed).
 */
export function findUnmigratedKeys(records) {
  const managed = new Set(
    records.filter((r) => r.service === MANAGED_SERVICE && r.account).map((r) => r.account)
  );
  const byName = new Map();
  for (const { service, account } of records) {
    let name = null;
    let store = null;
    if (service === GUI_SERVICE && account) {
      name = account;
      store = 'gui';
    } else if (service && service !== MANAGED_SERVICE && MANUAL_NAME_PATTERN.test(service)) {
      name = service;
      store = 'manual';
    }
    if (!name || managed.has(name)) continue;
    if (!byName.has(name)) byName.set(name, new Set());
    byName.get(name).add(store);
  }
  return [...byName.entries()]
    .map(([name, stores]) => ({ name, stores: [...stores].sort() }))
    .sort((a, b) => a.name.localeCompare(b.name));
}

/** Convenience wrapper around the live keychain dump (names/accts only). */
export async function listUnmigratedKeys() {
  const r = await security(['dump-keychain']);
  if (!r.ok) {
    throw new KeychainError(`failed to enumerate keychain items: ${r.stderr.trim()}`);
  }
  return findUnmigratedKeys(parseDump(r.stdout));
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
