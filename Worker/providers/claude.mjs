import { query } from '@anthropic-ai/claude-agent-sdk';
import { runtimeEnvironment } from './environment.mjs';
export async function claudeProposal({ prompt, schema, settings, cwd, signal }) {
  const controller = new AbortController();
  const abort = () => controller.abort();
  signal.addEventListener('abort', abort, { once: true });
  try {
    const stream = query({
      prompt,
      options: {
        cwd,
        model: settings.model || undefined,
        pathToClaudeCodeExecutable: settings.runtimePaths?.claudeSDK || undefined,
        tools: [],
        settingSources: [],
        mcpServers: {},
        strictMcpConfig: true,
        permissionMode: 'dontAsk',
        canUseTool: async () => ({ behavior: 'deny', message: 'Filing does not use tools.' }),
        persistSession: false,
        maxTurns: 3,
        abortController: controller,
        env: { ...runtimeEnvironment(), CLAUDE_AGENT_SDK_CLIENT_APP: 'paper-in/0.2.0' },
        outputFormat: { type: 'json_schema', schema },
      },
    });
    for await (const message of stream) {
      if (message.type === 'result') {
        if (message.subtype !== 'success' || message.is_error)
          throw new Error('Claude did not complete the classification.');
        if (message.structured_output) return message.structured_output;
        return JSON.parse(message.result);
      }
    }
    throw new Error('Claude returned no result.');
  } finally {
    signal.removeEventListener('abort', abort);
  }
}
