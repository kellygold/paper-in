import { workerSignal } from '../cancellation.mjs';
import { adapters } from './registry.mjs';
import { safeProviderError } from './environment.mjs';
import { proposalSchema, validateProposal } from '../schema.mjs';
export async function propose(options) {
  const provider = options.settings.provider;
  const run = adapters.get(provider);
  if (!run) throw new Error('Choose an AI provider.');
  try {
    return validateProposal(
      await run({
        ...options,
        schema: proposalSchema,
        signal: AbortSignal.any([workerSignal, AbortSignal.timeout(180000)]),
      }),
    );
  } catch (error) {
    throw new Error(safeProviderError(error));
  }
}
