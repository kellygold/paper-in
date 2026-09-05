import { workerSignal } from './cancellation.mjs';
import fs from 'node:fs/promises';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import {
  atomicJSON,
  readJSON,
  exists,
  hash,
  validRelative,
  confined,
  publishBytes,
  removeIfSame,
} from './files.mjs';
import { extract, documentContext, libraryContext } from './library.mjs';
import { promptFor, validateProposal } from './schema.mjs';

export class FilingEngine {
  constructor(root, { provider, ocr = extract, library = libraryContext, helper } = {}) {
    this.root = root;
    this.jobsDir = path.join(root, 'filing', 'jobs');
    this.provider = provider;
    this.ocr = ocr;
    this.library = library;
    this.helper = helper;
    this.issues = new Set();
  }
  jobDir(id) {
    if (!/^[0-9a-f-]{36}$/i.test(id)) throw new Error('Invalid job identity.');
    return path.join(this.jobsDir, id);
  }
  async save(job) {
    await atomicJSON(path.join(this.jobDir(job.id), 'job.json'), job);
  }
  async load(id) {
    const job = await readJSON(path.join(this.jobDir(id), 'job.json'));
    if (job.id !== id || typeof job.created !== 'string' || typeof job.state !== 'string')
      throw new Error('Invalid filing record.');
    return job;
  }
  async list() {
    await fs.mkdir(this.jobsDir, { recursive: true, mode: 0o700 });
    const jobs = [];
    for (const id of await fs.readdir(this.jobsDir)) {
      if (!/^[0-9a-f-]{36}$/i.test(id)) continue;
      try {
        jobs.push(await this.load(id));
      } catch (error) {
        // Discovery can be interrupted before job.json is committed. Keep other jobs usable.
        if (error.code !== 'ENOENT')
          this.issues.add('A filing record is unreadable. Its original PDF is preserved.');
      }
    }
    return jobs.sort((a, b) => b.created.localeCompare(a.created));
  }
  async discover() {
    const drafts = path.join(this.root, 'drafts');
    if (!(await exists(drafts))) return;
    for (const id of await fs.readdir(drafts)) {
      if (!/^[0-9a-f-]{36}$/i.test(id)) continue;
      try {
        const jobdir = this.jobDir(id),
          file = path.join(jobdir, 'job.json');
        if (await exists(file)) continue;
        const manifest = path.join(drafts, id, 'manifest.json');
        // A newly created draft directory may not have its manifest yet.
        if (!(await exists(manifest))) continue;
        const draft = await readJSON(manifest);
        const record = draft.export,
          intent = record?.filing;
        if (!record?.published || !intent) continue;
        await fs.mkdir(jobdir, { recursive: true, mode: 0o700 });
        const source = path.join(drafts, id, 'export.pdf'),
          bytes = await fs.readFile(source);
        if (hash(bytes) !== record.sha256) throw new Error('Export integrity check failed.');
        const snapshot = path.join(jobdir, 'original.pdf');
        if (!(await exists(snapshot))) await publishBytes(source, snapshot, record.sha256);
        else if (hash(await fs.readFile(snapshot)) !== record.sha256)
          throw new Error('Filing snapshot integrity check failed.');
        const original = new URL(record.destination).pathname;
        await this.save({
          id,
          created: new Date().toISOString(),
          state: 'queued',
          original: decodeURIComponent(original),
          root: intent.root,
          settings: intent.settings,
          sha256: record.sha256,
          proposal: null,
          error: null,
          target: null,
        });
      } catch {
        this.issues.add('A saved draft could not be prepared for filing. Other documents can continue; originals are preserved.');
      }
    }
  }
  async analyze(job, secrets = {}) {
    job.state = 'analyzing';
    job.error = null;
    await this.save(job);
    try {
      const snapshot = path.join(this.jobDir(job.id), 'original.pdf');
      if (hash(await fs.readFile(snapshot)) !== job.sha256)
        throw new Error('Saved PDF integrity check failed.');
      // Fail closed if the selected root is unavailable or replaced by a link.
      if ((await fs.realpath(job.root)) !== job.root) throw new Error('The filing folder changed.');
      const document = documentContext(await this.ocr(snapshot, this.helper));
      const context = await this.library(
        job.root,
        document,
        job.sha256,
        this.helper,
        path.join(this.root, 'filing', 'ocr-cache'),
      );
      const input = { document, ...context, rules: job.settings.rules || '' };
      const cwd = path.join(this.jobDir(job.id), 'runtime');
      await fs.mkdir(cwd, { recursive: true, mode: 0o700 });
      const ask = async (previous) =>
        validateProposal(
          await this.provider({
            prompt: promptFor(input, previous),
            settings: job.settings,
            cwd,
            secrets,
          }),
        );
      const first = await ask();
      const second = await ask(first);
      validRelative(second.filename, { pdf: true });
      if (second.filename.includes('/')) throw new Error('Filename must not contain directories.');
      validRelative(second.folder);
      await confined(job.root, second.folder + '/' + second.filename);
      const known = new Set(context.candidates.map((c) => c.path));
      if (second.related.some((r) => !known.has(r.path)))
        throw new Error('Provider referred to an unknown document.');
      const changed = first.folder !== second.folder || first.filename !== second.filename;
      second.needsReview ||=
        first.needsReview ||
        changed ||
        document.truncated ||
        document.lowConfidence ||
        document.lowText ||
        context.limited ||
        !!context.duplicate ||
        second.related.length > 0 ||
        !context.folders.includes(second.folder) ||
        Math.min(first.confidence, second.confidence) < 0.92;
      if (context.duplicate && !second.related.some((r) => r.path === context.duplicate))
        second.related.push({
          path: context.duplicate,
          relationship: 'duplicate',
          reason: 'Identical PDF bytes.',
        });
      job.proposal = second;
      job.contextSummary = {
        pages: document.pageCount,
        filesConsidered: context.filesConsidered,
        candidatesRead: context.candidates.length,
        truncated: document.truncated,
      };
      job.state = 'review';
      await this.save(job);
      if (job.settings.autoFile && !second.needsReview) await this.apply(job.id);
    } catch (error) {
      const saved = await this.load(job.id);
      if (['publishing', 'filed'].includes(saved.state)) throw error;
      saved.state = 'failed';
      saved.error = error.message || 'Filing failed; the PDF is safe.';
      await this.save(saved);
    }
  }
  async apply(id, override) {
    return this.attempt(id, () => this.publish(id, override));
  }
  async publish(id, override) {
    let job = await this.load(id);
    if (job.state === 'filed') return this.cleanupInbox(job);
    if (!['review', 'publishing'].includes(job.state))
      throw new Error('This document is not ready to file.');
    if (override) {
      if (job.state !== 'review') throw new Error('Publication already started.');
      job.proposal = { ...job.proposal, folder: override.folder, filename: override.filename };
    }
    const p = job.proposal;
    validRelative(p.folder);
    validRelative(p.filename, { pdf: true });
    if (p.filename.includes('/')) throw new Error('Filename must not contain directories.');
    if (!job.target) {
      const relative = p.folder + '/' + p.filename;
      let target = await confined(job.root, relative, true);
      if (await exists(target))
        target = await confined(
          job.root,
          p.folder + '/' + p.filename.slice(0, -4) + ' - ' + job.id.slice(0, 8) + '.pdf',
          true,
        );
      if (await exists(target))
        throw new Error('The output name is already in use. Choose another name.');
      job.target = target;
      job.state = 'publishing';
      await this.save(job);
    }
    const relative = path.relative(job.root, job.target);
    await confined(job.root, relative, true);
    if (await exists(job.target)) {
      if (hash(await fs.readFile(job.target)) !== job.sha256)
        throw new Error('The output changed. Nothing was overwritten.');
    } else await publishBytes(path.join(this.jobDir(id), 'original.pdf'), job.target, job.sha256);
    job.state = 'filed';
    job.error = null;
    job.cleanupPending = true;
    await this.save(job);
    return this.cleanupInbox(job);
  }
  async cleanupInbox(job) {
    if (job.cleanupPending === false) return job;
    try {
      // Cleanup is separate from the committed filing result and never follows links.
      if (job.original !== job.target &&
          path.dirname(job.original) === path.join(job.root, '_Inbox')) {
        await confined(job.root, path.relative(job.root, job.original));
        await removeIfSame(job.original, job.sha256);
      }
      job.cleanupPending = false;
      job.error = null;
    } catch {
      job.cleanupPending = true;
      job.error = 'Filed successfully. Inbox cleanup is paused; both copies are safe. Restore access to the inbox, then retry cleanup.';
    }
    await this.save(job);
    return job;
  }
  async attempt(id, action) {
    try {
      return await action();
    } catch (error) {
      // Preserve transaction state/targets so a retry resumes instead of starting over.
      const job = await this.load(id);
      job.error = ['publishing', 'undoing'].includes(job.state)
        ? 'Filing is paused. Check that the original destination is available, then retry. Your saved PDF is safe.'
        : (error.message || 'Filing could not finish. Your saved PDF is safe.');
      await this.save(job);
      throw error;
    }
  }
  async undo(id) {
    return this.attempt(id, () => this.restore(id));
  }
  async restore(id) {
    const job = await this.load(id);
    if (!['filed', 'undoing'].includes(job.state))
      throw new Error('Only a filed document can be undone.');
    if (!job.undoTarget) {
      let target = await confined(job.root, '_Inbox/' + path.basename(job.original), true);
      if (await exists(target))
        target = await confined(job.root, '_Inbox/Restored - ' + id + '.pdf', true);
      if (await exists(target)) throw new Error('Restore name is already in use.');
      job.undoTarget = target;
      job.state = 'undoing';
      await this.save(job);
    }
    await confined(job.root, path.relative(job.root, job.undoTarget), true);
    if (await exists(job.undoTarget)) {
      if (hash(await fs.readFile(job.undoTarget)) !== job.sha256)
        throw new Error('Restored file changed. Nothing was overwritten.');
    } else
      await publishBytes(path.join(this.jobDir(id), 'original.pdf'), job.undoTarget, job.sha256);
    await confined(job.root, path.relative(job.root, job.target));
    await removeIfSame(job.target, job.sha256);
    job.state = 'undone';
    job.original = job.undoTarget;
    job.error = null;
    await this.save(job);
    return job;
  }
  async retry(id, settings) {
    const job = await this.load(id);
    if (['publishing', 'undoing'].includes(job.state)) {
      job.error = null;
      await this.save(job);
      return;
    }
    if (!['failed', 'undone'].includes(job.state)) throw new Error('This job cannot be retried.');
    job.state = 'queued';
    job.error = null;
    job.target = null;
    job.undoTarget = null;
    if (settings) job.settings = settings;
    await this.save(job);
  }
  async run(secrets = {}) {
    this.issues.clear();
    await this.discover();
    for (const job of (await this.list()).reverse()) {
      if (workerSignal.aborted) break;
      try {
        if (['queued', 'analyzing'].includes(job.state)) await this.analyze(job, secrets);
        else if (job.state === 'publishing') await this.apply(job.id);
        else if (job.state === 'undoing') await this.undo(job.id);
        else if (job.state === 'filed' && job.cleanupPending !== false)
          await this.cleanupInbox(job);
      } catch {
        this.issues.add('One document could not finish filing. Other documents continued; open Saved documents to retry.');
      }
    }
    return [...this.issues];
  }

}
export async function withLock(root, action) {
  const folder = path.join(root, 'filing');
  await fs.mkdir(folder, { recursive: true, mode: 0o700 });
  const lock = path.join(folder, 'worker.lock');
  try {
    await fs.mkdir(lock);
  } catch (e) {
    if (e.code !== 'EEXIST') throw e;
    let pid;
    try {
      pid = Number(await fs.readFile(path.join(lock, 'pid'), 'utf8'));
    } catch {}
    if (!Number.isInteger(pid) || pid < 1) {
      const age = Date.now() - (await fs.stat(lock)).mtimeMs;
      if (age < 60000) throw new Error('Filing worker is starting. Try again shortly.');
    } else {
      try {
        process.kill(pid, 0);
        throw new Error('Filing is already running.');
      } catch (err) {
        if (err.code !== 'ESRCH') throw err;
      }
    }
    await fs.rm(lock, { recursive: true });
    await fs.mkdir(lock);
  }
  await fs.writeFile(path.join(lock, 'pid'), String(process.pid), { mode: 0o600 });
  try {
    return await action();
  } finally {
    await fs.rm(lock, { recursive: true, force: true });
  }
}
