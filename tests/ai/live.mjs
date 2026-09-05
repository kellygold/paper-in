// Explicit opt-in; synthetic text only. No real documents or folder names.
import { propose } from '../../ai/providers/index.mjs';
import { promptFor } from '../../ai/schema.mjs';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
const cwd = await fs.mkdtemp(path.join(os.tmpdir(), 'paper-in-live-'));
const provider = process.argv[2];
const settings = {
  provider,
  model: process.env.PAPER_IN_TEST_MODEL || '',
  runtimePaths: {
    claudeSDK: process.env.PAPER_IN_CLAUDE_PATH || '',
    codex: process.env.PAPER_IN_CODEX_PATH || '',
  },
};
try {
  const result = await propose({
    settings,
    cwd,
    secrets: { openaiAPI: process.env.OPENAI_API_KEY, anthropicAPI: process.env.ANTHROPIC_API_KEY },
    prompt: promptFor({
      document: {
        pageCount: 1,
        pages: [
          {
            page: 1,
            text: 'SYNTHETIC TEST INVOICE. Example Auto Workshop. Date 2026-08-14. Invoice DEMO-123. Vehicle service and oil change. Total AUD 120.00. This is fictional test data.',
          },
        ],
      },
      folders: ['Car/Servicing', 'Medical', 'Receipts'],
      candidates: [],
      rules: 'Use existing folders.',
    }),
  });
  if (result.folder !== 'Car/Servicing' || !result.filename.includes('2026-08-14'))
    throw new Error('Unexpected classification.');
  console.log(
    JSON.stringify({ provider, passed: true, folder: result.folder, filename: result.filename }),
  );
} finally {
  await fs.rm(cwd, { recursive: true, force: true });
}
