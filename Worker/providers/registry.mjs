import { readFileSync } from 'node:fs';
import { claudeProposal } from './claude.mjs';
import { codexProposal } from './codex.mjs';
import { apiProposal } from './api.mjs';

// Add an adapter here and a descriptor in provider-catalog.json. UI and key storage
// discover descriptors automatically; queue, prompts, validation and filing stay shared.
export const adapters = new Map([
  ['claudeSDK', claudeProposal],
  ['codex', codexProposal],
  ['openaiAPI', apiProposal],
  ['anthropicAPI', apiProposal],
]);
export const providerCatalog = JSON.parse(
  readFileSync(new URL('../provider-catalog.json', import.meta.url), 'utf8'),
);
if (providerCatalog.length !== adapters.size || providerCatalog.some((p) => !adapters.has(p.id)))
  throw new Error('Provider catalog and adapters do not match.');
