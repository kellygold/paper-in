import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { createRequire } from 'node:module';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { runtimeEnvironment } from './environment.mjs';

const execute = promisify(execFile);
const runtimeVersion = 'codex-cli 0.153.4';
// This policy is verified against the pinned runtime; a runtime upgrade needs a new check.
export const codexPolicy = [
  ...[
    'apps', 'plugins', 'remote_plugin', 'hooks', 'shell_tool', 'shell_snapshot',
    'browser_use', 'browser_use_external', 'browser_use_full_cdp_access', 'computer_use',
    'image_generation', 'multi_agent', 'multi_agent_v2', 'code_mode', 'code_mode_host',
    'code_mode_only', 'view_image', 'in_app_local_automation', 'in_app_browser',
    'sleep_tool', 'goals', 'auth_elicitation', 'tool_call_mcp_elicitation', 'realtime_conversation',
    'tool_suggest', 'skill_search', 'skill_mcp_dependency_install', 'workspace_dependencies', 'artifact',
  ].map((name) => `features.${name}=false`),
  'tools.view_image=false', 'tools.web_search=false', 'web_search="disabled"', 'notify=[]', 'project_doc_max_bytes=0',
];

async function canonical(file) {
  try { return await fs.realpath(file); }
  catch (error) {
    if (error.code !== 'ENOENT') throw error;
    return path.resolve(file);
  }
}
async function checkProjectConfig(cwd, env) {
  const globalConfig = await canonical(path.join(env.CODEX_HOME || path.join(env.HOME || os.homedir(), '.codex'), 'config.toml'));
  let directory = await fs.realpath(cwd);
  // mcp list enumerates the global config. Refuse project layers it cannot enumerate.
  for (;;) {
    const config = path.join(directory, '.codex', 'config.toml');
    try {
      await fs.lstat(config);
      if (await canonical(config) !== globalConfig)
        throw new Error('Project configuration is not supported in the filing runtime directory.');
    } catch (error) { if (error.code !== 'ENOENT') throw error; }
    const parent = path.dirname(directory);
    if (parent === directory) break;
    directory = parent;
  }
}
export async function prepareCodexRuntime({ settings, cwd, signal, env = runtimeEnvironment() }) {
  await checkProjectConfig(cwd, env);
  const command = settings.runtimePaths?.codex;
  const sdkRequire = createRequire(import.meta.resolve('@openai/codex-sdk'));
  const executable = command || process.execPath;
  const prefix = command ? [] : [sdkRequire.resolve('@openai/codex/bin/codex.js')];
  const run = async (args) => {
    try {
      const { stdout } = await execute(executable, [...prefix, ...args], {
        cwd, env, signal, timeout: 10000, maxBuffer: 1024 * 1024,
      });
      return stdout;
    } catch {
      // Config output can contain user-defined environment secrets. Never surface it.
      throw new Error('Could not verify Codex runtime isolation. Check the pinned runtime and configuration.');
    }
  };
  if ((await run(['--version'])).trim() !== runtimeVersion)
    throw new Error('This Codex runtime version has not been validated for filing. Use the bundled SDK runtime.');
  const list = async (overrides) => {
    const raw = await run(['mcp', 'list', '--json', ...overrides.flatMap((value) => ['-c', value])]);
    let servers;
    try { servers = JSON.parse(raw); } catch { throw new Error('Codex returned invalid configuration.'); }
    if (!Array.isArray(servers) || servers.some((s) => !s || typeof s.name !== 'string' || !s.name || typeof s.enabled !== 'boolean'))
      throw new Error('Codex returned an unsupported configuration.');
    return servers;
  };
  const servers = await list(codexPolicy);
  // An empty table recursively merges; enumerate names and disable each using TOML keys,
  // not dotted paths (server names themselves may contain dots, quotes or Unicode).
  const disableMCP = 'mcp_servers={' + servers.map((s) => `${JSON.stringify(s.name)}={enabled=false}`).join(',') + '}';
  const configOverrides = [...codexPolicy, disableMCP];
  if ((await list(configOverrides)).some((s) => s.enabled !== false))
    throw new Error('Codex tools could not be disabled. Filing is paused.');
  return { env, configOverrides };
}
