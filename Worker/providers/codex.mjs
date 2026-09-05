import { Codex } from '@openai/codex-sdk';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { runtimeEnvironment } from './environment.mjs';
export async function codexProposal({ prompt, schema, settings, cwd, signal }) {
  // Disable user-configured MCP servers as well as built-in execution/search.
  let configText = '';
  try {
    configText = await readFile(
      path.join(process.env.CODEX_HOME || path.join(os.homedir(), '.codex'), 'config.toml'),
      'utf8',
    );
  } catch (e) {
    if (e.code !== 'ENOENT') throw e;
  }
  const configOverrides = [];
  for (const match of configText.matchAll(/^\[mcp_servers\.([^\]]+)\]/gm))
    configOverrides.push(`mcp_servers.${match[1]}.enabled=false`);
  const codex = new Codex({
    codexPathOverride: settings.runtimePaths?.codex || undefined,
    env: runtimeEnvironment(),
    configOverrides,
    config: {
      features: { shell_tool: false, apps: false },
      web_search: 'disabled',
      project_doc_max_bytes: 0,
    },
  });
  const thread = codex.startThread({
    model: settings.model || undefined,
    workingDirectory: cwd,
    skipGitRepoCheck: true,
    sandboxMode: 'read-only',
    approvalPolicy: 'never',
    networkAccessEnabled: false,
    webSearchMode: 'disabled',
    modelReasoningEffort: 'low',
  });
  const result = await thread.run(prompt, { outputSchema: schema, signal });
  if (
    result.items.some((i) =>
      ['command_execution', 'file_change', 'mcp_tool_call', 'web_search'].includes(i.type),
    )
  )
    throw new Error('Unexpected tool use.');
  return JSON.parse(result.finalResponse);
}
