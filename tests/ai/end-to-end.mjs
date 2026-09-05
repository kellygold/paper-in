// Opt-in live integration: Swift export handoff -> local OCR -> provider -> file -> undo.
import { FilingEngine } from '../../ai/engine.mjs';
import { propose } from '../../ai/providers/index.mjs';
import { hash } from '../../ai/files.mjs';
import fs from 'node:fs/promises';
import path from 'node:path';
const root = await fs.realpath(process.argv[2]);
const engine = new FilingEngine(root, {
  provider: propose,
  helper: path.resolve('.build/Paper In.app/Contents/Resources/PaperOCR'),
});
await engine.run({
  openaiAPI: process.env.OPENAI_API_KEY,
  anthropicAPI: process.env.ANTHROPIC_API_KEY,
});
const jobs = await engine.list();
if (jobs.length !== 1) throw new Error('Unexpected number of jobs.');
let job = jobs[0];
if (!['filed', 'review'].includes(job.state)) throw new Error(job.error || 'Filing incomplete');
if (job.proposal.folder !== 'Car/Servicing' || !job.proposal.filename.includes('2026-08-14'))
  throw new Error('Incorrect synthetic invoice classification');
if (job.state === 'review') await engine.apply(job.id);
job = await engine.load(job.id);
if (hash(await fs.readFile(job.target)) !== job.sha256) throw new Error('Filed bytes changed');
await engine.undo(job.id);
job = await engine.load(job.id);
if (hash(await fs.readFile(job.original)) !== job.sha256) throw new Error('Restored bytes changed');
console.log(
  JSON.stringify({
    provider: job.settings.provider,
    passed: true,
    pages: job.contextSummary.pages,
    filename: job.proposal.filename,
    finalState: job.state,
  }),
);
