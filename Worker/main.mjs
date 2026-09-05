import { cancelWorker } from './cancellation.mjs';
process.once('SIGTERM', cancelWorker);
process.once('SIGINT', cancelWorker);
import { FilingEngine, withLock } from './engine.mjs';
import { propose } from './providers/index.mjs';
let raw = '';
for await (const chunk of process.stdin) {
  raw += chunk;
  if (raw.length > 1000000) throw new Error('Request too large.');
}
try {
  const request = JSON.parse(raw),
    engine = new FilingEngine(request.root, { provider: propose, helper: request.helper });
  await withLock(request.root, async () => {
    if (request.command === 'run') await engine.run(request.secrets || {});
    else if (request.command === 'apply') await engine.apply(request.id, request.override);
    else if (request.command === 'undo') await engine.undo(request.id);
    else if (request.command === 'retry') await engine.retry(request.id, request.settings);
    else if (request.command !== 'list') throw new Error('Unknown filing command.');
  });
  process.stdout.write(JSON.stringify({ ok: true }));
} catch (error) {
  process.stdout.write(JSON.stringify({ ok: false, error: error.message || 'Filing failed.' }));
  process.exitCode = 1;
}
