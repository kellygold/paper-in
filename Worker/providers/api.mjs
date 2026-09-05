export async function apiProposal({
  prompt,
  schema,
  settings,
  signal,
  secrets,
  fetchImpl = fetch,
}) {
  const anthropic = settings.provider === 'anthropicAPI';
  const key = secrets?.[settings.provider];
  if (!key) throw Object.assign(new Error('Missing API key.'), { status: 401 });
  if (!settings.model?.trim()) throw new Error('Set an API model in AI settings.');
  const endpoint = anthropic
    ? 'https://api.anthropic.com/v1/messages'
    : 'https://api.openai.com/v1/responses';
  const headers = anthropic
    ? { 'x-api-key': key, 'anthropic-version': '2023-06-01' }
    : { Authorization: `Bearer ${key}` };
  const body = anthropic
    ? {
        model: settings.model,
        max_tokens: 4096,
        messages: [{ role: 'user', content: prompt }],
        output_config: { format: { type: 'json_schema', schema } },
      }
    : {
        model: settings.model,
        store: false,
        input: prompt,
        max_output_tokens: 4096,
        text: { format: { type: 'json_schema', name: 'filing_proposal', strict: true, schema } },
      };
  const response = await fetchImpl(endpoint, {
    method: 'POST',
    headers: { ...headers, 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
    signal,
    redirect: 'error',
  });
  if (!response.ok)
    throw Object.assign(new Error('API request failed.'), { status: response.status });
  const data = await response.json();
  if (anthropic) {
    if (data.stop_reason !== 'end_turn') throw new Error('Incomplete API result.');
    return JSON.parse(
      data.content
        .filter((c) => c.type === 'text')
        .map((c) => c.text)
        .join(''),
    );
  }
  if (data.status !== 'completed') throw new Error('Incomplete API result.');
  return JSON.parse(
    data.output
      .flatMap((o) => o.content || [])
      .filter((c) => c.type === 'output_text')
      .map((c) => c.text)
      .join(''),
  );
}
