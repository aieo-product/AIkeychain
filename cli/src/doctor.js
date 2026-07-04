// `akc doctor` — diagnose whether keychain:// references and shell config can
// resolve correctly. Secret values are never printed (masked only).

import { readFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { collectRefs, resolveRefs } from './run.js';
import { listKeys, resolveKey, listAmbiguousDuplicates, KeychainError } from './keychain.js';

const pExecFile = promisify(execFile);

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
    if (svc) {
      if (svc[1] === 'com.aieo.aikeychain') {
        // GUI 保存形式で pin された行 (`-s "com.aieo.aikeychain" -a "KEY"`) では
        // 実際のキー名は -a 側にある。-s の値 (共通サービス名) ではなく -a を採る。
        const acct = find[1].match(/-a\s+"?([A-Za-z_][A-Za-z0-9_]*)"?/);
        if (acct) keys.add(acct[1]);
      } else {
        keys.add(svc[1]);
      }
    }
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

/** Detect a bare (PATH-dependent, issue #131) `akc` MCP registration for Codex. */
async function checkCodexMcpRegistration(check, codexTomlPath) {
  let text = '';
  try {
    text = await readFile(codexTomlPath, 'utf8');
  } catch {
    return; // no Codex config — nothing to check
  }
  if (/^\s*command\s*=\s*"akc"\s*$/m.test(text)) {
    check(
      'mcp registration (codex)',
      false,
      `${codexTomlPath} registers aikeychain with a bare "akc" command (PATH-dependent — ` +
        'may fail from launchd/cron or after a Node version switch). Re-run `akc init` to ' +
        'switch to an absolute path.'
    );
  } else if (text.includes('[mcp_servers.aikeychain]')) {
    check('mcp registration (codex)', true, 'aikeychain registered with a PATH-independent absolute path');
  }
}

/** Detect a bare (PATH-dependent, issue #131) `akc` MCP registration for Claude Code. */
async function checkClaudeMcpRegistration(check) {
  let stdout;
  try {
    ({ stdout } = await pExecFile('claude', ['mcp', 'list'], { timeout: 15000 }));
  } catch {
    return; // claude CLI not installed / not on PATH — nothing to check
  }
  const line = stdout.split('\n').find((l) => /^\s*aikeychain[:\s]/.test(l));
  if (!line) return; // not registered — orthogonal to this check
  if (/\bakc\s+mcp\b/.test(line) && !line.includes('/')) {
    check(
      'mcp registration (claude)',
      false,
      'Claude Code registers aikeychain with a bare "akc" command (PATH-dependent — may fail ' +
        'from GUI apps/cron or after a Node version switch). Re-run `akc init` to switch to an ' +
        'absolute path.'
    );
  } else {
    check('mcp registration (claude)', true, 'aikeychain registered with a PATH-independent absolute path');
  }
}

export async function runDoctor({ env = process.env, zshrcPath, codexTomlPath } = {}) {
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

  // MCP registration path-independence (issue #131): warn on bare `akc`.
  await checkCodexMcpRegistration(check, codexTomlPath ?? join(homedir(), '.codex', 'config.toml'));
  await checkClaudeMcpRegistration(check);

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
