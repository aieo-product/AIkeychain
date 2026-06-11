// Thin wrapper around the macOS `security` CLI.
// Lookup order matches scripts/akc (issue #91):
//   1. service="com.aieo.aikeychain" account="<KEY>"  (AI KeyChain GUI store)
//   2. service="<KEY>" with NO account               (manually-registered keys)
// Manual keys are looked up by service only because their `acct` attribute is
// not consistent ($USER or the service name) — pinning -a can grab a stale
// duplicate entry and return an invalid value.

import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const pExecFile = promisify(execFile);

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
    const { stdout, stderr } = await pExecFile('security', args, {
      maxBuffer: 16 * 1024 * 1024,
    });
    return { ok: true, stdout, stderr };
  } catch (err) {
    return { ok: false, stdout: err.stdout ?? '', stderr: err.stderr ?? String(err) };
  }
}

function stripTrailingNewline(s) {
  return s.endsWith('\n') ? s.slice(0, -1) : s;
}

/** Resolve a key to its secret value, or null if not found. */
export async function resolveKey(name) {
  let r = await security(['find-generic-password', '-s', GUI_SERVICE, '-a', name, '-w']);
  if (r.ok) {
    const value = stripTrailingNewline(r.stdout);
    if (value) return value;
  }
  r = await security(['find-generic-password', '-s', name, '-w']);
  if (r.ok) {
    const value = stripTrailingNewline(r.stdout);
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

/**
 * Store a key. Defaults to the AI KeyChain GUI store so the entry shows up in
 * the app. `-U` updates in place to avoid acct-mismatched duplicates.
 * Limitation: `security add-generic-password` only accepts the value via -w,
 * so the secret is briefly visible in the `security` child's argv to other
 * processes of the same user. The security CLI has no stdin mode; avoiding
 * this would require a native Keychain API helper.
 */
export async function setKey(name, value, { manual = false } = {}) {
  if (!name) throw new KeychainError('key name is required');
  if (!value) throw new KeychainError('refusing to store an empty value');
  const service = manual ? name : GUI_SERVICE;
  const r = await security(['add-generic-password', '-U', '-s', service, '-a', name, '-w', value]);
  if (!r.ok) {
    throw new KeychainError(`failed to save "${name}": ${r.stderr.trim() || 'unknown error'}`);
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

export function maskValue(value) {
  return `****** (${value.length} chars)`;
}
