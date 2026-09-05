import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { prepareCodexRuntime } from '../../ai/providers/codex-isolation.mjs';

test('pinned Codex disables servers across TOML syntax without running them or notification hooks', async (t) => {
  const root = await fs.realpath(await fs.mkdtemp(path.join(os.tmpdir(), 'paper-in-isolation-')));
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const home = path.join(root, 'home'), cwd = path.join(root, 'job/runtime');
  await fs.mkdir(home, { recursive: true });
  await fs.mkdir(cwd, { recursive: true });
  const marker = path.join(root, 'unexpected-execution');
  const notify = `notify=["/usr/bin/touch",${JSON.stringify(marker)}]\n`;
  const configs = [
    notify + `mcp_servers={"inline.name"={command="/usr/bin/touch",args=[${JSON.stringify(marker)}]}}\n`,
    notify + `[mcp_servers."quoted name"]\ncommand="/usr/bin/touch"\nargs=[${JSON.stringify(marker)}]\n[mcp_servers."quoted name".env]\nSYNTHETIC="example"\n`,
  ];
  for (const [index, config] of configs.entries()) {
    await fs.writeFile(path.join(home, 'config.toml'), config);
    const result = await prepareCodexRuntime({ settings: {}, cwd, env: { PATH: process.env.PATH, HOME: root, CODEX_HOME: home } });
    assert.ok(result.configOverrides.at(-1).includes(index === 0 ? '"inline.name"={enabled=false}' : '"quoted name"={enabled=false}'));
    assert.equal(await fs.readFile(path.join(home, 'config.toml'), 'utf8'), config);
    await assert.rejects(fs.stat(marker), { code: 'ENOENT' });
  }
  await fs.mkdir(path.join(root, 'job/.codex'));
  await fs.writeFile(path.join(root, 'job/.codex/config.toml'), '[mcp_servers.project]\ncommand="/usr/bin/true"\n');
  await assert.rejects(prepareCodexRuntime({ settings: {}, cwd, env: { HOME: root, CODEX_HOME: home } }), /Project configuration/);
});
