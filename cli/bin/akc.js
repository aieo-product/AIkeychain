#!/usr/bin/env node
// akc — AI KeyChain CLI
// Secret-reference resolver + key management + MCP server for AI agents.

import { createRequire } from 'node:module';
import {
  assertMacOS,
  keyExists,
  listKeys,
  resolveKey,
  setKey,
  deleteKey,
  maskValue,
  KeychainError,
  MANAGED_SERVICE,
} from '../src/keychain.js';
import { cmdRun } from '../src/run.js';
import { runDoctor, formatReport } from '../src/doctor.js';
import { USAGE_GUIDE } from '../src/usage-guide.js';

const require = createRequire(import.meta.url);
const { version } = require('../package.json');

const USAGE = `akc — AI KeyChain CLI (secret references, key management, MCP server)

Usage:
  akc init [--print] [--no-register] [--local]
  akc run [--dry-run] -- <command> [args...]
  akc list
  akc check <KEY>
  akc get <KEY> [--reveal]
  akc set <KEY>
  akc delete <KEY>
  akc doctor
  akc guide
  akc mcp
  akc version
  akc help

Commands:
  init     Set up agent discoverability machine-wide: write ~/.claude/CLAUDE.md
           + ~/.codex/AGENTS.md instructions, register the MCP server (Claude user
           scope + ~/.codex/config.toml). --local scopes it to the current project,
           --print previews, --no-register skips MCP registration.
  run      Resolve keychain:// env references and execute a command
  list     List known key names (never prints values)
  check    Check whether a key exists and in which store
  get      Print the keychain:// reference for a key (--reveal prints the raw value)
  set      Store/update a key (value via hidden prompt, or piped stdin)
  delete   Delete a key from the Keychain
  doctor   Diagnose env + ~/.zshrc refs + unmigrated legacy keys (values masked)
  guide    Print the AI KeyChain usage guide
  mcp      Start the MCP server on stdio (for Claude Code / Codex etc.)

Examples:
  akc init                        # set up every AI session on this machine (Claude + Codex)
  export OPENAI_API_KEY=keychain://OPENAI_API_KEY
  akc run -- claude
  akc set GITHUB_TOKEN            # prompts for the value (hidden)
  claude mcp add aikeychain -- akc mcp
`;

function readSecretFromTTY(promptText) {
  return new Promise((resolve, reject) => {
    process.stderr.write(promptText);
    const stdin = process.stdin;
    stdin.setRawMode(true);
    stdin.resume();
    stdin.setEncoding('utf8');
    let value = '';
    const cleanup = () => {
      stdin.setRawMode(false);
      stdin.pause();
      stdin.off('data', onData);
    };
    const onData = (chunk) => {
      for (const ch of chunk) {
        if (ch === '\r' || ch === '\n' || ch === '\u0004') {
          cleanup();
          process.stderr.write('\n');
          resolve(value);
          return;
        }
        if (ch === '\u0003') {
          cleanup();
          process.stderr.write('\n');
          reject(new KeychainError('cancelled'));
          return;
        }
        if (ch === '\u007f' || ch === '\b') {
          value = value.slice(0, -1);
        } else {
          value += ch;
        }
      }
    };
    stdin.on('data', onData);
  });
}

async function readSecret(keyName) {
  if (!process.stdin.isTTY) {
    let data = '';
    for await (const chunk of process.stdin) data += chunk;
    return data.replace(/\r?\n$/, '');
  }
  return readSecretFromTTY(`Enter value for ${keyName} (input hidden): `);
}

async function cmdList() {
  const keys = await listKeys();
  if (keys.length === 0) {
    process.stdout.write('No keys found.\n');
    return 0;
  }
  for (const { name } of keys) {
    process.stdout.write(`  ${name}\n`);
  }
  return 0;
}

async function cmdCheck(name) {
  const result = await keyExists(name);
  if (result.exists) {
    process.stdout.write(`✅ ${name} exists (managed store)\n`);
    // The bare `security -s <KEY> -w` form (no -a) returns exit 44 for managed
    // items — a false "not registered" signal (issue #137). Show the right form.
    process.stdout.write(
      `   ↳ security CLI: use -s "${MANAGED_SERVICE}" -a "${name}" -w  (or: akc get ${name})\n`
    );
    return 0;
  }
  process.stdout.write(`❌ ${name} not found in Keychain\n`);
  return 1;
}

async function cmdGet(name, { reveal }) {
  if (!reveal) {
    const result = await keyExists(name);
    if (!result.exists) {
      process.stderr.write(`akc: ${name} not found in Keychain\n`);
      return 1;
    }
    process.stdout.write(`keychain://${name}\n`);
    return 0;
  }
  const value = await resolveKey(name);
  if (value === null) {
    process.stderr.write(`akc: ${name} not found in Keychain\n`);
    return 1;
  }
  if (process.stdout.isTTY) {
    process.stderr.write('akc: printing raw secret value to terminal\n');
  }
  process.stdout.write(`${value}\n`);
  return 0;
}

async function cmdSet(name) {
  const value = await readSecret(name);
  if (!value) {
    process.stderr.write('akc: empty value, nothing saved\n');
    return 1;
  }
  const saved = await setKey(name, value);
  process.stdout.write(
    `✅ Saved ${name} (${maskValue(value)}) to service "${saved.service}"\n`
  );
  return 0;
}

async function cmdDelete(name) {
  const removed = await deleteKey(name);
  if (!removed) {
    process.stderr.write(`akc: ${name} not found in Keychain\n`);
    return 1;
  }
  process.stdout.write(`✅ Deleted ${name}\n`);
  return 0;
}

function requireKeyArg(argv, command) {
  const name = argv.find((a) => !a.startsWith('--'));
  if (!name) {
    process.stderr.write(`akc: missing key name\nUsage: akc ${command} <KEY>\n`);
    return null;
  }
  return name;
}

async function main() {
  const [command, ...rest] = process.argv.slice(2);

  switch (command ?? 'help') {
    case 'help':
    case '--help':
    case '-h':
      process.stdout.write(USAGE);
      return 0;
    case 'version':
    case '--version':
    case '-V':
      process.stdout.write(`akc ${version}\n`);
      return 0;
    case 'guide':
      process.stdout.write(USAGE_GUIDE);
      return 0;
    case 'init': {
      const { cmdInit } = await import('../src/init.js');
      return cmdInit(rest);
    }
  }

  assertMacOS();

  switch (command) {
    case 'run':
      return cmdRun(rest);
    case 'list':
      return cmdList();
    case 'check': {
      const name = requireKeyArg(rest, 'check');
      return name === null ? 1 : cmdCheck(name);
    }
    case 'get': {
      const name = requireKeyArg(rest, 'get');
      return name === null ? 1 : cmdGet(name, { reveal: rest.includes('--reveal') });
    }
    case 'set': {
      const name = requireKeyArg(rest, 'set');
      if (rest.includes('--manual')) {
        // #167: every write targets the managed namespace; the legacy manual
        // scheme is read-only. The old --manual path could create
        // acct-mismatched duplicates (issue #91).
        process.stderr.write(
          'akc: --manual is no longer supported: all writes go to the managed namespace\n'
        );
        return 1;
      }
      return name === null ? 1 : cmdSet(name);
    }
    case 'delete': {
      const name = requireKeyArg(rest, 'delete');
      return name === null ? 1 : cmdDelete(name);
    }
    case 'doctor': {
      const report = await runDoctor();
      process.stdout.write(`${formatReport(report)}\n`);
      return report.ok ? 0 : 1;
    }
    case 'mcp': {
      const { startMcpServer } = await import('../src/mcp-server.js');
      await startMcpServer();
      return new Promise(() => {}); // serve until the transport closes the process
    }
    default:
      process.stderr.write(`akc: unknown command: ${command}\n`);
      process.stderr.write(USAGE);
      return 1;
  }
}

main()
  .then((code) => {
    process.exitCode = code;
  })
  .catch((err) => {
    if (err instanceof KeychainError) {
      process.stderr.write(`akc: ${err.message}\n`);
    } else {
      process.stderr.write(`akc: unexpected error: ${err?.stack ?? err}\n`);
    }
    process.exitCode = 1;
  });
