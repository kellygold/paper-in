import { Codex } from '@openai/codex-sdk';
import { prepareCodexRuntime } from './codex-isolation.mjs';
export async function codexProposal({ prompt, schema, settings, cwd, signal }) {
  const isolation = await prepareCodexRuntime({ settings, cwd, signal });
  const codex = new Codex({
    codexPathOverride: settings.runtimePaths?.codex || undefined,
    ...isolation,
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
      !['agent_message', 'reasoning', 'todo_list', 'error'].includes(i.type),
    )
  )
    throw new Error('Unexpected tool use.');
  return JSON.parse(result.finalResponse);
}
