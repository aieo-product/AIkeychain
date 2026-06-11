// `akc run [--dry-run] -- <command> [args...]`
// Resolves keychain:// references in the environment and runs the command with
// the resolved values injected. The parent process env is never modified.
// Behavior is compatible with scripts/akc (bash).

import { spawn } from 'node:child_process';
import { resolveKey, maskValue } from './keychain.js';

export const REF_PREFIX = 'keychain://';

/** Collect keychain:// references from an env object. */
export function collectRefs(env) {
  return Object.entries(env)
    .filter(([, value]) => typeof value === 'string' && value.startsWith(REF_PREFIX))
    .map(([varName, value]) => ({ varName, keyName: value.slice(REF_PREFIX.length) }));
}

/** Resolve refs sequentially (parallel lookups can stack keychain auth prompts). */
export async function resolveRefs(refs) {
  const resolved = {};
  const failed = [];
  for (const { varName, keyName } of refs) {
    const value = await resolveKey(keyName);
    if (value) {
      resolved[varName] = value;
    } else {
      failed.push({ varName, keyName });
    }
  }
  return { resolved, failed };
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
        process.stderr.write(`  ❌ ${varName} — keychain://${keyName} not found in Keychain\n`);
      }
    }
    process.stdout.write(`\nResolved: ${Object.keys(resolved).length}, Failed: ${failed.length}\n`);
    if (failed.length > 0) {
      process.stdout.write('Register missing keys in AI KeyChain or macOS Keychain.\n');
    }
    return 0;
  }

  if (failed.length > 0) {
    for (const { varName, keyName } of failed) {
      process.stderr.write(`  ❌ ${varName} — keychain://${keyName} not found in Keychain\n`);
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

  return new Promise((resolve) => {
    child.on('error', (err) => {
      process.stderr.write(`akc: failed to run ${command[0]}: ${err.message}\n`);
      resolve(127);
    });
    child.on('exit', (code, signal) => {
      resolve(code ?? (signal ? 1 : 0));
    });
  });
}
