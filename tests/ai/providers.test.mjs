import { test } from 'node:test';
import assert from 'node:assert/strict';
import { apiProposal } from '../../ai/providers/api.mjs';
import { safeProviderError, runtimeEnvironment } from '../../ai/providers/environment.mjs';
import { proposalSchema } from '../../ai/schema.mjs';
const proposal = {
  folder: 'Medical',
  filename: 'Undated - Example.pdf',
  confidence: 0.8,
  reason: 'Example',
  needsReview: true,
  related: [],
};
for (const provider of ['openaiAPI', 'anthropicAPI'])
  test(provider + ' sends structured schema and parses complete response', async () => {
    let called = false;
    const result = await apiProposal({
      prompt: 'synthetic',
      schema: proposalSchema,
      settings: { provider, model: 'test-model' },
      secrets: { [provider]: 'synthetic-key' },
      signal: AbortSignal.timeout(1000),
      fetchImpl: async (url, options) => {
        called = true;
        assert.equal(options.redirect, 'error');
        const body = JSON.parse(options.body);
        assert.equal(body.model, 'test-model');
        if (provider === 'openaiAPI') {
          assert.equal(url, 'https://api.openai.com/v1/responses');
          assert.equal(options.headers.Authorization, 'Bearer synthetic-key');
          assert.deepEqual(body.text.format.schema, proposalSchema);
          return {
            ok: true,
            json: async () => ({
              status: 'completed',
              output: [{ content: [{ type: 'output_text', text: JSON.stringify(proposal) }] }],
            }),
          };
        }
        assert.equal(url, 'https://api.anthropic.com/v1/messages');
        assert.equal(options.headers['x-api-key'], 'synthetic-key');
        assert.deepEqual(body.output_config.format.schema, proposalSchema);
        return {
          ok: true,
          json: async () => ({
            stop_reason: 'end_turn',
            content: [{ type: 'text', text: JSON.stringify(proposal) }],
          }),
        };
      },
    });
    assert.ok(called);
    assert.deepEqual(result, proposal);
  });
test('missing keys and API failures surface without leaking response or key', async () => {
  await assert.rejects(
    () => apiProposal({ settings: { provider: 'openaiAPI', model: 'test' }, secrets: {} }),
    (e) => e.status === 401,
  );
  for (const status of [401, 403, 429, 500]) {
    try {
      await apiProposal({
        settings: { provider: 'openaiAPI', model: 'test' },
        secrets: { openaiAPI: 'secret' },
        fetchImpl: async () => ({ ok: false, status }),
      });
      assert.fail();
    } catch (e) {
      assert.equal(e.status, status);
      assert.ok(!safeProviderError(e).includes('secret'));
    }
  }
  assert.ok(!safeProviderError(new Error('secret medical details')).includes('medical'));
});
test('truncated provider response is rejected', async () => {
  await assert.rejects(
    () =>
      apiProposal({
        settings: { provider: 'openaiAPI', model: 'test' },
        secrets: { openaiAPI: 'test' },
        fetchImpl: async () => ({
          ok: true,
          json: async () => ({ status: 'incomplete', output: [] }),
        }),
      }),
    /Incomplete/,
  );
});
test('runtime environment excludes provider keys and bearer tokens', () => {
  process.env.PAPER_IN_TEST_SECRET_TOKEN = 'secret';
  assert.equal(runtimeEnvironment().PAPER_IN_TEST_SECRET_TOKEN, undefined);
  delete process.env.PAPER_IN_TEST_SECRET_TOKEN;
});

test('provider catalog and adapters define the same extensible surface', async () => {
  const { providerCatalog, adapters } = await import('../../ai/providers/registry.mjs');
  assert.equal(new Set(providerCatalog.map((p) => p.id)).size, providerCatalog.length);
  assert.deepEqual([...adapters.keys()].sort(), providerCatalog.map((p) => p.id).sort());
  for (const descriptor of providerCatalog) {
    assert.ok(['runtime', 'apiKey'].includes(descriptor.authentication));
    assert.equal(typeof descriptor.requiresModel, 'boolean');
    assert.ok(descriptor.name && descriptor.help);
  }
});
