import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { FilingEngine, withLock } from '../engine.mjs';
import { atomicJSON, hash, exists, confined, validRelative } from '../files.mjs';
import { validateProposal } from '../schema.mjs';
const id = '11111111-1111-4111-8111-111111111111';
const proposal = () => ({
  folder: 'Car/Servicing',
  filename: '2026-08-14 - Example Auto - Service.pdf',
  confidence: 0.97,
  reason: 'Vehicle servicing invoice; date and issuer are printed on the document.',
  needsReview: false,
  related: [],
});
async function setup(t, { provider = async () => proposal(), context = {} } = {}) {
  const root = await fs.realpath(await fs.mkdtemp(path.join(os.tmpdir(), 'paper-in-test-')));
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const destination = path.join(root, 'Scans');
  await fs.mkdir(path.join(destination, '_Inbox'), { recursive: true });
  await fs.mkdir(path.join(destination, 'Car/Servicing'), { recursive: true });
  const data = Buffer.from('%PDF synthetic preserved bytes'),
    original = path.join(destination, '_Inbox', 'scan.pdf');
  await fs.writeFile(original, data);
  const draft = path.join(root, 'drafts', id);
  await fs.mkdir(draft, { recursive: true });
  await fs.writeFile(path.join(draft, 'export.pdf'), data);
  await atomicJSON(path.join(draft, 'manifest.json'), {
    id,
    export: {
      destination: new URL('file://' + original).href,
      sha256: hash(data),
      published: true,
      filing: { root: destination, settings: { provider: 'codex', autoFile: true } },
    },
  });
  const engine = new FilingEngine(root, {
    provider,
    ocr: async () => ({
      pageCount: 1,
      pages: [
        {
          page: 1,
          text: 'Example Auto vehicle service invoice August 14 2026, reference ABC123, amount $120.',
          confidence: 1,
        },
      ],
    }),
    library: async () => ({
      folders: ['Car/Servicing'],
      candidates: [],
      filesConsidered: 0,
      limited: false,
      ...context,
    }),
  });
  return { root, destination, data, original, engine };
}
test('exports discovered exactly once; two-pass filing and undo preserve original bytes', async (t) => {
  let calls = 0;
  const { engine, data, original } = await setup(t, {
    provider: async () => {
      calls++;
      return proposal();
    },
  });
  await engine.run();
  await engine.run();
  assert.equal(calls, 2);
  assert.equal((await engine.list()).length, 1);
  let job = await engine.load(id);
  assert.equal(job.state, 'filed');
  assert.deepEqual(await fs.readFile(job.target), data);
  assert.equal(await exists(original), false);
  await engine.undo(id);
  job = await engine.load(id);
  assert.equal(job.state, 'undone');
  assert.deepEqual(await fs.readFile(job.original), data);
  assert.equal(await exists(job.target), false);
  assert.deepEqual(await fs.readFile(path.join(engine.jobDir(id), 'original.pdf')), data);
});
test('second-pass disagreement forces review without changing inbox', async (t) => {
  let calls = 0;
  const { engine, original } = await setup(t, {
    provider: async () => ({ ...proposal(), filename: ++calls === 1 ? 'first.pdf' : 'second.pdf' }),
  });
  await engine.run();
  assert.equal((await engine.load(id)).state, 'review');
  assert.equal(await exists(original), true);
});
test('duplicates and new categories always require review', async (t) => {
  const { engine } = await setup(t, {
    context: {
      duplicate: 'Car/existing.pdf',
      candidates: [{ path: 'Car/existing.pdf' }],
      folders: [],
    },
  });
  await engine.run();
  const job = await engine.load(id);
  assert.equal(job.state, 'review');
  assert.equal(job.proposal.related[0].relationship, 'duplicate');
});
test('provider failure preserves PDF and can retry', async (t) => {
  const { engine, original, data } = await setup(t, {
    provider: async () => {
      throw new Error('Simulated unavailable provider');
    },
  });
  await engine.run();
  assert.equal((await engine.load(id)).state, 'failed');
  assert.deepEqual(await fs.readFile(original), data);
  engine.provider = async () => proposal();
  await engine.retry(id);
  await engine.run();
  assert.equal((await engine.load(id)).state, 'filed');
});
test('path traversal, absolute paths, dot folders and nested filename are rejected', async (t) => {
  for (const path of [
    '../escape.pdf',
    '/escape.pdf',
    'Car/../../x',
    'Car//x',
    '.hidden/x',
    'Car\\x',
    'Car/x\u0000',
  ])
    assert.throws(() => validRelative(path));
  const { engine, original } = await setup(t, {
    provider: async () => ({ ...proposal(), folder: '../outside' }),
  });
  await engine.run();
  assert.equal((await engine.load(id)).state, 'failed');
  assert.equal(await exists(original), true);
});
test('symlink destinations cannot escape selected root', async (t) => {
  const { engine, destination, root } = await setup(t);
  await fs.symlink(root, path.join(destination, 'Linked'));
  await assert.rejects(() => confined(destination, 'Linked/file.pdf', true), /symbolic/);
  engine.provider = async () => ({ ...proposal(), folder: 'Linked' });
  await engine.run();
  assert.equal((await engine.load(id)).state, 'failed');
});
test('existing files are not overwritten and undo preserves externally edited output', async (t) => {
  const { engine, destination } = await setup(t);
  const existing = path.join(destination, 'Car/Servicing', proposal().filename);
  await fs.writeFile(existing, 'existing unrelated content');
  await engine.run();
  let job = await engine.load(id);
  assert.notEqual(job.target, existing);
  assert.equal(await fs.readFile(existing, 'utf8'), 'existing unrelated content');
  await fs.writeFile(job.target, 'user changed this');
  await engine.undo(id);
  assert.equal(await fs.readFile(job.target, 'utf8'), 'user changed this');
});
test('publication interrupted after linking resumes idempotently', async (t) => {
  const { engine, destination } = await setup(t);
  await engine.discover();
  let job = await engine.load(id);
  job.state = 'review';
  job.proposal = proposal();
  await engine.save(job);
  const originalSave = engine.save.bind(engine);
  engine.save = async (value) => {
    if (value.state === 'filed') throw new Error('Simulated commit failure');
    return originalSave(value);
  };
  await assert.rejects(() => engine.apply(id));
  engine.save = originalSave;
  assert.equal((await engine.load(id)).state, 'publishing');
  await engine.run();
  assert.equal((await engine.load(id)).state, 'filed');
  assert.equal(
    (await fs.readdir(path.join(destination, 'Car/Servicing'))).filter((f) => f.endsWith('.pdf'))
      .length,
    1,
  );
});
test('interrupted analysis is retried after restart', async (t) => {
  const { engine } = await setup(t);
  await engine.discover();
  const job = await engine.load(id);
  job.state = 'analyzing';
  await engine.save(job);
  await engine.run();
  assert.equal((await engine.load(id)).state, 'filed');
});
test('unknown related paths rejected; model cannot direct deletion or extra fields', async (t) => {
  assert.throws(() => validateProposal({ ...proposal(), delete: '/tmp/anything' }));
  const { engine } = await setup(t, {
    provider: async () => ({
      ...proposal(),
      related: [{ path: 'not-supplied.pdf', relationship: 'duplicate', reason: 'made up' }],
    }),
  });
  await engine.run();
  assert.equal((await engine.load(id)).state, 'failed');
});
test('worker lock excludes concurrent actions and releases on failure', async (t) => {
  const { root } = await setup(t);
  await withLock(root, async () => {
    await assert.rejects(() => withLock(root, async () => {}), /already running/);
  });
  await assert.rejects(() =>
    withLock(root, async () => {
      throw new Error('failure');
    }),
  );
  await withLock(root, async () => {});
});
test('weak OCR retains review state', async (t) => {
  const { engine } = await setup(t);
  engine.ocr = async () => ({
    pageCount: 1,
    pages: [
      {
        page: 1,
        text: 'This document has enough text but recognition is uncertain.',
        confidence: 0.5,
      },
    ],
  });
  await engine.run();
  assert.equal((await engine.load(id)).state, 'review');
});
test('interrupted Undo resumes without a second restore', async (t) => {
  const { engine } = await setup(t);
  await engine.run();
  const originalSave = engine.save.bind(engine);
  engine.save = async (job) => {
    if (job.state === 'undone') throw new Error('Simulated final commit failure');
    return originalSave(job);
  };
  await assert.rejects(() => engine.undo(id));
  engine.save = originalSave;
  assert.equal((await engine.load(id)).state, 'undoing');
  await engine.run();
  const job = await engine.load(id);
  assert.equal(job.state, 'undone');
  assert.equal(
    (await fs.readdir(path.dirname(job.original))).filter((f) => f.endsWith('.pdf')).length,
    1,
  );
});
test('a damaged source snapshot never publishes', async (t) => {
  const { engine, original, data } = await setup(t);
  await engine.discover();
  await fs.writeFile(path.join(engine.jobDir(id), 'original.pdf'), 'damaged');
  await engine.run();
  assert.equal((await engine.load(id)).state, 'failed');
  assert.deepEqual(await fs.readFile(original), data);
});
test('abandoned lock without a PID can recover after its startup grace period', async (t) => {
  const { root } = await setup(t);
  const lock = path.join(root, 'filing', 'worker.lock');
  await fs.mkdir(lock, { recursive: true });
  const before = new Date(Date.now() - 120000);
  await fs.utimes(lock, before, before);
  await withLock(root, async () => {});
  assert.equal(await exists(lock), false);
});
