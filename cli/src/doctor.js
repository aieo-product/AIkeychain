// `akc doctor` — diagnose whether keychain:// references and shell config can
// resolve correctly. Secret values are never printed (masked only).

import { readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { homedir } from 'node:os';
import { join, isAbsolute } from 'node:path';
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

// --- MCP registration path-independence (issue #131) ---
//
// A registration whose `command` is the bare `akc` is PATH-dependent and fails
// from GUI apps / cron / launchd or after a Node version switch. An absolute
// path is PATH-independent — but Homebrew/nvm delete old version dirs on
// upgrade, so an absolute path that no longer exists on disk is *also* broken
// (just differently). Both need to be flagged so the user re-runs `akc init`.

/** Pull the `command` value out of the [mcp_servers.aikeychain] table in a config.toml. */
export function extractCodexAikeychainCommand(text) {
  const lines = text.split('\n');
  let inTable = false;
  for (const raw of lines) {
    const line = raw.trim();
    if (/^\[.+\]$/.test(line)) {
      inTable = line === '[mcp_servers.aikeychain]';
      continue;
    }
    if (!inTable || line.startsWith('#')) continue;
    const m = line.match(/^command\s*=\s*"((?:[^"\\]|\\.)*)"/);
    if (m) return m[1].replace(/\\(.)/g, '$1'); // unescape TOML basic string
  }
  return null;
}

/**
 * Classify an MCP registration `command` for path-independence.
 * Returns null when there is nothing to check, else { ok, kind, command }.
 * `exists` is injectable so tests stay hermetic (no real filesystem probing).
 */
export function classifyMcpCommand(command, { exists = existsSync } = {}) {
  if (typeof command !== 'string' || command.length === 0) return null;
  if (command === 'akc' || !isAbsolute(command)) return { ok: false, kind: 'bare', command };
  if (!exists(command)) return { ok: false, kind: 'stale', command };
  return { ok: true, kind: 'absolute', command };
}

function mcpDetail(agent, result) {
  if (result.ok) return `aikeychain registered with an existing absolute path (PATH-independent)`;
  if (result.kind === 'bare') {
    return (
      `${agent} registers aikeychain with a bare "${result.command}" command (PATH-dependent — ` +
      'may fail from GUI apps/cron/launchd or after a Node version switch). Re-run `akc init` ' +
      'to register an absolute path.'
    );
  }
  return (
    `${agent} registers aikeychain at "${result.command}" which no longer exists on disk ` +
    '(stale — e.g. a Node upgrade removed the old version dir). Re-run `akc init` to refresh it.'
  );
}

async function checkCodexMcpRegistration(check, codexTomlPath) {
  let text;
  try {
    text = await readFile(codexTomlPath, 'utf8');
  } catch {
    return; // no Codex config — nothing to check
  }
  const result = classifyMcpCommand(extractCodexAikeychainCommand(text));
  if (result) check('mcp registration (codex)', result.ok, mcpDetail('Codex', result));
}

async function checkClaudeMcpRegistration(check, claudeJsonPath) {
  let json;
  try {
    json = JSON.parse(await readFile(claudeJsonPath, 'utf8'));
  } catch {
    return; // no ~/.claude.json / unparseable — nothing to check
  }
  const entry = json?.mcpServers?.aikeychain;
  const result = entry && classifyMcpCommand(entry.command);
  if (result) check('mcp registration (claude)', result.ok, mcpDetail('Claude Code', result));
}

export async function runDoctor({ env = process.env, zshrcPath, codexTomlPath, claudeJsonPath } = {}) {
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

  // MCP registration path-independence (issue #131): warn on bare `akc` or a
  // stale absolute path. Read config files directly (read-only, testable) —
  // no `claude mcp list` (which health-checks every server and can hang).
  await checkCodexMcpRegistration(check, codexTomlPath ?? join(homedir(), '.codex', 'config.toml'));
  await checkClaudeMcpRegistration(check, claudeJsonPath ?? join(homedir(), '.claude.json'));

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
