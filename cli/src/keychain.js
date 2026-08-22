// Thin wrapper around the macOS `security` CLI.
// v2.0 (#188): a single managed namespace is the ONLY store. Every key lives at
//   service="com.aieo.aikeychain.managed" account="<KEY>"
// created by /usr/bin/security, so headless reads never prompt or hang. The
// legacy GUI store / manual scheme from v1.x are no longer read or written —
// pre-v2 users re-register their keys (`akc set <KEY>`). This drops the old
// 3-tier lookup, migration-required errors, and all legacy fallbacks.

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

// v2.0 (#188): the single managed namespace. Every key created by
// /usr/bin/security lives here and is headless-readable without prompts.
export const MANAGED_SERVICE = 'com.aieo.aikeychain.managed';

export class KeychainError extends Error {}

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
// can be exercised without waiting 10s). Strictly validated (#185 S3): a
// positive integer between 100ms and 600s — anything else (floats break
// execFile's integer timeout, tiny values would fail healthy reads, huge
// values clamp weirdly in Node's timers) falls back to the default.
const timeoutOverride = process.env.AIKEYCHAIN_SUBPROCESS_TIMEOUT_MS;
export const SUBPROCESS_TIMEOUT_MS =
  typeof timeoutOverride === 'string' &&
  /^\d+$/.test(timeoutOverride) &&
  Number(timeoutOverride) >= 100 &&
  Number(timeoutOverride) <= 600_000
    ? Number(timeoutOverride)
    : 10_000;

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
 * Resolve a key to its secret value, or null if not found (v2.0: managed only).
 * Managed items are security-owned and never prompt — a timeout means the
 * keychain is locked/unavailable; a non-44 error fails closed with a reason.
 */
export async function resolveKey(name) {
  const r = await security(['find-generic-password', '-s', MANAGED_SERVICE, '-a', name, '-w']);
  if (r.ok) {
    const value = stripTrailingNewline(r.stdout);
    return value || null;
  }
  if (r.code === 44) return null;
  if (r.timedOut) {
    throw new KeychainError(
      `reading "${name}" timed out — the keychain is likely locked or unavailable. ` +
        'Unlock the login keychain and retry.'
    );
  }
  // fail closed on unexpected errors (#147/#150 semantics), with a reason (#185 S4)
  throw new KeychainError(
    `reading "${name}" failed (exit ${r.code}): ${r.stderr.trim() || 'unknown error'}`
  );
}

/**
 * Check whether a key exists without reading its secret value (v2.0: managed only).
 * Fails closed (#150): only exit 44 means "not found" — any other failure throws.
 */
export async function keyExists(name) {
  const r = await security(['find-generic-password', '-s', MANAGED_SERVICE, '-a', name]);
  if (r.ok) return { name, exists: true };
  if (r.code === 44) return { name, exists: false };
  throw new KeychainError(
    `keychain probe failed (exit ${r.code}): ${r.stderr.trim() || 'unknown error'}`
  );
}

/**
 * Redact hex-encoded secret material from text destined for errors/logs.
 * Not only `-X <hex>`: when a line overflows the `security -i` buffer the tool
 * echoes the overflow chunks as `unknown command "<hex>"` with no -X prefix
 * (#191), so any hex run long enough to be secret material is redacted too.
 */
export function redactSecrets(text) {
  return text
    .replace(/-X\s+[0-9a-fA-F]+/g, '-X <redacted>')
    .replace(/[0-9a-fA-F]{8,}/g, '<redacted>');
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

// `security -i` reads one command per line through a 4096-byte fgets buffer.
// A line of 4095 chars fills it exactly, leaving the newline to be read as an
// empty follow-up command whose exit 0 masks the real command's status; 4096+
// chars are split and the tail is parsed as further commands (#191 — measured
// on the real binary: 4094 -> real status, 4095/4096 -> exit 0 masked, 4097 ->
// `unknown command "<tail>"`). So the usable line is 4094 chars incl. nothing
// but the command; the newline is reserved. The write command is
//   add-generic-password -U -s "<managed>" -a "<KEY>" -X <hex>
// whose prefix is 66 chars + the key name, and the hex value takes 2 chars per
// byte, so the usable value length is (4094 - 66 - name.length) / 2 ≈ 2000 for
// typical key names. Matches the Swift service (SecurityCLIKeychainService
// .maxValueLength(forAccount:)). Hex stays on purpose: it is the structural
// guard against `security -i` tokenizer injection, not an encoding detail —
// longer values are out of scope rather than switching to quoted -w.
export const SECURITY_I_LINE_MAX = 4094;

function writeCommandPrefix(name) {
  return `add-generic-password -U -s "${MANAGED_SERVICE}" -a "${name}" -X `;
}

/** Longest value (in characters) that `setKey(name, …)` can store. */
export function maxValueLength(name) {
  return Math.max(0, Math.floor((SECURITY_I_LINE_MAX - writeCommandPrefix(name).length) / 2));
}

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
  const limit = maxValueLength(name);
  if (value.length > limit) {
    throw new KeychainError(
      `value exceeds the ${limit}-character limit for "${name}" ` +
        `(security -i line budget: (${SECURITY_I_LINE_MAX} - 66 - key name length) / 2; ` +
        'longer values are not supported)'
    );
  }
  // All writes target the managed namespace (#167). The legacy manual scheme
  // is no longer a write target (the old --manual path could create
  // acct-mismatched duplicates — the exact #91 failure mode).
  const service = MANAGED_SERVICE;
  const hex = Buffer.from(value, 'utf8').toString('hex');
  const r = await securityInteractive(`${writeCommandPrefix(name)}${hex}`);
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
 * Delete a key from the managed namespace (v2.0: managed only).
 * Returns true if an item was removed, false if it was not found (exit 44 is
 * benign/idempotent); any other failure throws.
 */
export async function deleteKey(name) {
  const r = await security(['delete-generic-password', '-s', MANAGED_SERVICE, '-a', name]);
  if (r.ok) return true;
  if (r.code === 44) return false;
  throw new KeychainError(
    `failed to delete "${name}" (exit ${r.code}): ${r.stderr.trim() || 'unknown error'}`
  );
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
 * List known keys (names only — secret values are never read; v2.0: managed only).
 * Returns [{ name }] sorted by name.
 */
export async function listKeys() {
  const r = await security(['dump-keychain']);
  if (!r.ok) {
    throw new KeychainError(`failed to enumerate keychain items: ${r.stderr.trim()}`);
  }
  const names = new Set();
  for (const { service, account } of parseDump(r.stdout)) {
    if (service === MANAGED_SERVICE && account) names.add(account);
  }
  return [...names]
    .map((name) => ({ name }))
    .sort((a, b) => a.name.localeCompare(b.name));
}

/** One dump-keychain call, parsed into { service, account } records (names/accts only). */
export async function dumpRecords() {
  const r = await security(['dump-keychain']);
  if (!r.ok) {
    throw new KeychainError(`failed to enumerate keychain items: ${r.stderr.trim()}`);
  }
  return parseDump(r.stdout);
}

// 固定長マスク。桁数（value.length）は出さない: 正確な長さは総当たりコストを
// 下げる・キー種別/世代を識別できるメタデータで、端末スクロールバックや
// エビデンスキャプチャに残る（scripts/akc は #115/#123 で対応済み。CLI 側も統一）。
export function maskValue(_value) {
  return '********';
}
