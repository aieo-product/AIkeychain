// MCP (Model Context Protocol) server over stdio: `akc mcp`
// Design rule: no tool ever returns a raw secret value to the model.
// Agents get keychain:// references and run workloads through `akc run`.

import { createRequire } from 'node:module';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { z } from 'zod';
import { keyExists, listKeys, setKey, deleteKey } from './keychain.js';
import { runDoctor, formatReport } from './doctor.js';
import { USAGE_GUIDE } from './usage-guide.js';

const require = createRequire(import.meta.url);
const { version } = require('../package.json');

const text = (s) => ({ content: [{ type: 'text', text: s }] });
const json = (o) => text(JSON.stringify(o, null, 2));

const keyNameSchema = z
  .string()
  .regex(/^[A-Za-z0-9_.-]+$/, 'key name must match [A-Za-z0-9_.-]+')
  .describe('Key name, usually an env-var-style name like GITHUB_TOKEN');

export function buildServer() {
  const server = new McpServer({ name: 'aikeychain', version });

  server.registerTool(
    'usage_guide',
    {
      description:
        'How to use AI KeyChain correctly (keychain:// references, akc run, security CLI rules). ' +
        'Call this first if you are unsure how secrets are managed on this machine.',
      inputSchema: {},
    },
    async () => text(USAGE_GUIDE)
  );

  server.registerTool(
    'list_keys',
    {
      description:
        'List key names stored in the macOS Keychain (AI KeyChain GUI store + manually-registered ' +
        'env-var-style keys). Returns names and where they live — never secret values.',
      inputSchema: {},
    },
    async () => json(await listKeys())
  );

  server.registerTool(
    'check_key',
    {
      description:
        'Check whether a key exists in the Keychain and in which store (app = AI KeyChain GUI, ' +
        'manual = service-name entry). Does not read the secret value.',
      inputSchema: { name: keyNameSchema },
    },
    async ({ name }) => json(await keyExists(name))
  );

  server.registerTool(
    'get_secret_reference',
    {
      description:
        'Get the keychain:// reference string for a key. Use the reference as an env var value and ' +
        'run the workload via `akc run -- <command>` — the raw secret is injected into the child ' +
        'process only and never enters the model context.',
      inputSchema: { name: keyNameSchema },
    },
    async ({ name }) => {
      const exists = await keyExists(name);
      return json({
        reference: `keychain://${name}`,
        exists: exists.exists,
        stores: { app: exists.app, manual: exists.manual },
        usage: `export ${name}=keychain://${name} && akc run -- <command>`,
      });
    }
  );

  server.registerTool(
    'set_secret',
    {
      description:
        'Store or update a key in the AI KeyChain store (overwrites in place, no duplicates). ' +
        'CAUTION: the secret value passes through the model context when you call this tool — ' +
        'prefer asking the user to run `akc set <KEY>` themselves unless they explicitly pasted ' +
        'the value into the conversation already.',
      inputSchema: {
        name: keyNameSchema,
        value: z.string().min(1).describe('The secret value to store'),
        manual: z
          .boolean()
          .optional()
          .describe('Store as a manual entry (service=<name>) instead of the AI KeyChain GUI store'),
      },
    },
    async ({ name, value, manual }) => {
      const saved = await setKey(name, value, { manual: manual ?? false });
      return json({ saved: true, service: saved.service, account: saved.account });
    }
  );

  server.registerTool(
    'delete_secret',
    {
      description:
        'Delete a key from the Keychain (both the AI KeyChain store and manual entries). ' +
        'Destructive — requires confirm=true, and you should confirm with the user first.',
      inputSchema: {
        name: keyNameSchema,
        confirm: z.boolean().describe('Must be true to actually delete'),
      },
    },
    async ({ name, confirm }) => {
      if (!confirm) {
        return json({ deleted: [], note: 'confirm=true is required to delete' });
      }
      const deleted = await deleteKey(name);
      return json({ deleted, found: deleted.length > 0 });
    }
  );

  server.registerTool(
    'doctor',
    {
      description:
        'Diagnose the local setup: keychain access, keychain:// references in the current ' +
        'environment, and ~/.zshrc patterns (including the -a "$USER" pitfall). Values are masked.',
      inputSchema: {},
    },
    async () => {
      const report = await runDoctor();
      return text(formatReport(report));
    }
  );

  return server;
}

export async function startMcpServer() {
  const server = buildServer();
  await server.connect(new StdioServerTransport());
}
