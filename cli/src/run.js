// `akc run [--dry-run] -- <command> [args...]`
// Resolves keychain:// references in the environment and runs the command with
// the resolved values injected. The parent process env is never modified.
// Behavior is compatible with scripts/akc (bash).

import { spawn } from 'node:child_process';
import { constants as osConstants } from 'node:os';
import { resolveKey, maskValue, KeychainError, SUBPROCESS_TIMEOUT_MS } from './keychain.js';

export const REF_PREFIX = 'keychain://';

/** Collect keychain:// references from an env object. */
export function collectRefs(env) {
  return Object.entries(env)
    .filter(([, value]) => typeof value === 'string' && value.startsWith(REF_PREFIX))
    .map(([varName, value]) => ({ varName, keyName: value.slice(REF_PREFIX.length) }));
}

/**
 * Resolve refs sequentially (parallel lookups can stack keychain auth prompts).
 * Failures carry a `reason`: null for plain not-found, or a bounded-failure
 * message from resolveKey (migration required / keychain locked — #171).
 * One key's bounded failure must not abort the scan (the user should see ALL
 * broken refs at once) — but the scan as a whole is still bounded (#185 S7):
 * - duplicate keyNames are resolved once (cache)
 * - after `deadlineMs`, remaining unresolved keys are skipped with an
 *   explanatory reason instead of stacking N x timeout
 */
export async function resolveRefs(refs, { deadlineMs = SUBPROCESS_TIMEOUT_MS * 3 } = {}) {
  const resolved = {};
  const failed = [];
  const cache = new Map(); // keyName -> { value } | { err }
  const deadline = Date.now() + deadlineMs;
  for (const { varName, keyName } of refs) {
    let entry = cache.get(keyName);
    if (!entry) {
      if (Date.now() > deadline) {
        entry = {
          err: new KeychainError(
            'skipped: command deadline exceeded after earlier keychain timeouts — ' +
              'fix the keys reported above, then retry (see `akc doctor`)'
          ),
        };
      } else {
        try {
          entry = { value: await resolveKey(keyName) };
        } catch (err) {
          if (!(err instanceof KeychainError)) throw err;
          entry = { err };
        }
      }
      cache.set(keyName, entry);
    }
    if (entry.err) {
      failed.push({ varName, keyName, reason: entry.err.message });
    } else if (entry.value) {
      resolved[varName] = entry.value;
    } else {
      failed.push({ varName, keyName, reason: null });
    }
  }
  return { resolved, failed };
}

function failureLine(varName, keyName, reason) {
  return reason
    ? `  ❌ ${varName} — keychain://${keyName}: ${reason}
`
    : `  ❌ ${varName} — keychain://${keyName} not found in Keychain
`;
}

export async function cmdRun(argv) {
  let dryRun = false;
  let hasSeparator = false;
  let i = 0;
  for (; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--dry-run') {
      dryRun = true;
    } else if (arg === '--') {
      hasSeparator = true;
      i++;
      break;
    } else {
      process.stderr.write(`akc: unknown option: ${arg}\n`);
      process.stderr.write('Usage: akc run [--dry-run] -- <command> [args...]\n');
      return 1;
    }
  }
  const command = argv.slice(i);

  if (!dryRun && !hasSeparator) {
    process.stderr.write("akc: missing '--' separator before command\n");
    process.stderr.write('Usage: akc run [--dry-run] -- <command> [args...]\n');
    return 1;
  }

  const refs = collectRefs(process.env);
  const { resolved, failed } = await resolveRefs(refs);

  if (dryRun) {
    for (const { varName, keyName } of refs) {
      if (varName in resolved) {
        process.stdout.write(
          `  ✅ ${varName} = ${maskValue(resolved[varName])} (from keychain://${keyName})\n`
        );
      } else {
        const reason = failed.find((f) => f.varName === varName)?.reason;
        process.stderr.write(failureLine(varName, keyName, reason));
      }
    }
    process.stdout.write(`\nResolved: ${Object.keys(resolved).length}, Failed: ${failed.length}\n`);
    if (failed.length > 0) {
      process.stdout.write('Register missing keys in AI KeyChain or macOS Keychain.\n');
    }
    return 0;
  }

  if (failed.length > 0) {
    for (const { varName, keyName, reason } of failed) {
      process.stderr.write(failureLine(varName, keyName, reason));
    }
    process.stderr.write(`akc: ${failed.length} keychain reference(s) could not be resolved\n`);
    process.stderr.write("akc: run 'akc run --dry-run' to see details\n");
    return 1;
  }

  if (command.length === 0) {
    process.stderr.write("akc: no command specified after '--'\n");
    return 1;
  }

  const child = spawn(command[0], command.slice(1), {
    stdio: 'inherit',
    env: { ...process.env, ...resolved },
  });

  // Unlike the bash version (which execs), a wrapper process remains: forward
  // termination signals to the child and reproduce conventional exit codes.
  const forwarded = ['SIGINT', 'SIGTERM', 'SIGHUP'];
  const forward = (sig) => child.kill(sig);

  return new Promise((resolve) => {
    const done = (code) => {
      for (const sig of forwarded) process.off(sig, forward);
      resolve(code);
    };
    for (const sig of forwarded) process.on(sig, forward);
    child.on('error', (err) => {
      process.stderr.write(`akc: failed to run ${command[0]}: ${err.message}\n`);
      done(127);
    });
    child.on('exit', (code, signal) => {
      done(signal ? 128 + (osConstants.signals[signal] ?? 1) : code ?? 0);
    });
  });
}
