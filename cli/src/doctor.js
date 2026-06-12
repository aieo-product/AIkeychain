// `akc doctor` — diagnose whether keychain:// references and shell config can
// resolve correctly. Secret values are never printed (masked only).

import { readFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { collectRefs, resolveRefs } from './run.js';
import { listKeys, resolveKey, listAmbiguousDuplicates, KeychainError } from './keychain.js';

/** Extract keychain://KEY and `security find-generic-password -s "KEY"` keys from shell config text. */
export function scanShellConfig(text) {
  const keys = new Set();
  const warnings = [];
  for (const m of text.matchAll(/keychain:\/\/([A-Za-z0-9_.-]+)/g)) {
    keys.add(m[1]);
  }
  for (const line of text.split('\n')) {
    if (line.trimStart().startsWith('#')) continue;
    const find = line.match(/security\s+find-generic-password\s+([^\n]*)/);
    if (!find) continue;
    const svc = find[1].match(/-s\s+"?([A-Za-z0-9_.-]+)"?/);
    if (svc) keys.add(svc[1]);
    if (/-a\s+"\$USER"|-a\s+\$USER/.test(find[1])) {
      // Report the service name only — never echo the raw shell line, which
      // could contain inline secrets or other sensitive content.
      warnings.push(
        `${svc ? svc[1] : '(unknown key)'}: lookup uses -a "$USER" — account attributes are ` +
          'inconsistent; look up by service only (issue #91)'
      );
    }
  }
  return { keys: [...keys].sort(), warnings };
}

export async function runDoctor({ env = process.env, zshrcPath } = {}) {
  const report = { platform: process.platform, checks: [], warnings: [], ok: true };
  const check = (name, ok, detail) => {
    report.checks.push({ name, ok, detail });
    if (!ok) report.ok = false;
  };

  if (process.platform !== 'darwin') {
    check('platform', false, 'not macOS — the `security` command is unavailable');
    return report;
  }
  check('platform', true, 'macOS');

  // GUI / manual store reachability (names only)
  let appKeyCount = null;
  try {
    const keys = await listKeys();
    appKeyCount = keys.filter((k) => k.sources.includes('app')).length;
    check('keychain access', true, `${keys.length} key(s) visible (${appKeyCount} in AI KeyChain store)`);
  } catch (err) {
    if (err instanceof KeychainError) {
      check('keychain access', false, err.message);
    } else {
      throw err;
    }
  }

  // Ambiguous duplicate entries (issue #91): same service name, multiple accts.
  try {
    const dups = await listAmbiguousDuplicates();
    if (dups.length === 0) {
      check('duplicate entries', true, 'no ambiguous duplicate keychain entries');
    } else {
      check(
        'duplicate entries',
        false,
        `${dups.length} service(s) have duplicate entries — \`security -s NAME -w\` is ambiguous:\n` +
          dups
            .map(
              (d) =>
                `       - ${d.service}: acct=[${d.accounts.map((a) => `"${a}"`).join(', ')}]` +
                ` → remove the stale one: security delete-generic-password -s "${d.service}" -a "<acct>"`
            )
            .join('\n')
      );
    }
  } catch (err) {
    if (!(err instanceof KeychainError)) throw err;
    // keychain access already reported above; skip duplicate scan on failure
  }

  // Environment keychain:// references
  const refs = collectRefs(env);
  if (refs.length === 0) {
    check('env references', true, 'no keychain:// references in current environment');
  } else {
    const { resolved, failed } = await resolveRefs(refs);
    check(
      'env references',
      failed.length === 0,
      `${Object.keys(resolved).length}/${refs.length} resolved` +
        (failed.length ? ` — missing: ${failed.map((f) => f.keyName).join(', ')}` : '')
    );
  }

  // ~/.zshrc scan
  const path = zshrcPath ?? join(homedir(), '.zshrc');
  let text = null;
  try {
    text = await readFile(path, 'utf8');
  } catch {
    check('shell config', true, `${path} not found (skipped)`);
  }
  if (text !== null) {
    const { keys, warnings } = scanShellConfig(text);
    report.warnings.push(...warnings);
    if (keys.length === 0) {
      check('shell config', true, `no keychain references in ${path}`);
    } else {
      const missing = [];
      for (const key of keys) {
        const value = await resolveKey(key);
        if (!value) missing.push(key);
      }
      check(
        'shell config',
        missing.length === 0,
        `${keys.length - missing.length}/${keys.length} key(s) in ${path} resolvable` +
          (missing.length ? ` — missing: ${missing.join(', ')}` : '')
      );
    }
  }

  return report;
}

export function formatReport(report) {
  const lines = [];
  for (const { name, ok, detail } of report.checks) {
    lines.push(`  ${ok ? '✅' : '❌'} ${name}: ${detail}`);
  }
  for (const warning of report.warnings) {
    lines.push(`  ⚠️  ${warning}`);
  }
  lines.push('');
  lines.push(report.ok ? 'All checks passed.' : 'Some checks failed. See above.');
  return lines.join('\n');
}
