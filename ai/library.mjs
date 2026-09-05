import { workerSignal } from './cancellation.mjs';
import fs from 'node:fs/promises';
import path from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { hash, readJSON, atomicJSON, confined } from './files.mjs';
const execute = promisify(execFile);
export async function extract(pdf, helper) {
  const { stdout } = await execute(helper, [pdf], {
    timeout: 180000,
    signal: workerSignal,
    maxBuffer: 12 * 1024 * 1024,
  });
  const result = JSON.parse(stdout);
  if (
    !Number.isInteger(result.pageCount) ||
    !Array.isArray(result.pages) ||
    result.pages.length !== result.pageCount
  )
    throw new Error('Local OCR returned incomplete pages.');
  return result;
}
export function documentContext(ocr) {
  let budget = 65000,
    truncated = false;
  const pages = ocr.pages.map((p) => {
    const text = p.text.slice(0, Math.min(10000, budget));
    budget -= text.length;
    if (text.length < p.text.length) truncated = true;
    return { page: p.page, text, confidence: p.confidence };
  });
  return {
    pageCount: ocr.pageCount,
    pages,
    truncated,
    lowConfidence: ocr.pages.some((p) => p.text.trim().length > 0 && p.confidence < 0.85),
    lowText: ocr.pages.reduce((n, p) => n + p.text.trim().length, 0) < 30,
  };
}
export async function libraryContext(root, document, snapshotHash, helper, cacheDir) {
  const files = [],
    folders = new Set();
  let limited = false;
  async function walk(dir, depth = 0) {
    const entries = await fs.readdir(dir, { withFileTypes: true });
    for (const entry of entries.sort((a, b) => a.name.localeCompare(b.name))) {
      workerSignal.throwIfAborted();
      if (entry.name.startsWith('.') || entry.name.startsWith('_') || entry.isSymbolicLink())
        continue;
      const file = path.join(dir, entry.name),
        relative = path.relative(root, file);
      if (entry.isDirectory()) {
        folders.add(relative);
        if (depth < 5) await walk(file, depth + 1);
        else limited = true;
      } else if (entry.isFile() && entry.name.toLowerCase().endsWith('.pdf')) {
        if (files.length < 1500) files.push(relative);
        else limited = true;
      }
    }
  }
  await walk(root);
  const words = new Set(
    document.pages.flatMap((p) => p.text.toLowerCase().match(/[a-z0-9]{4,}/g) || []),
  );
  const ranked = files
    .map((relative) => ({
      path: relative,
      score: (relative.toLowerCase().match(/[a-z0-9]{4,}/g) || []).reduce(
        (n, w) => n + (words.has(w) ? 1 : 0),
        0,
      ),
    }))
    .sort((a, b) => b.score - a.score || a.path.localeCompare(b.path));
  await fs.mkdir(cacheDir, { recursive: true, mode: 0o700 });
  const candidates = [];
  let duplicate = null;
  // Byte hashes for all candidates; OCR only the strongest eight. Cached OCR aids future retrieval.
  for (const entry of ranked) {
    workerSignal.throwIfAborted();
    const file = await confined(root, entry.path),
      st = await fs.stat(file);
    if (st.size > 512 * 1024 * 1024) {
      limited = true;
      continue;
    }
    const fingerprint = hash(await fs.readFile(file));
    if (fingerprint === snapshotHash) {
      duplicate = entry.path;
      continue;
    }
    const cacheFile = path.join(cacheDir, fingerprint + '.json');
    let ocr;
    try {
      ocr = await readJSON(cacheFile);
    } catch (e) {
      if (e.code !== 'ENOENT') {
        limited = true;
      }
    }
    if (ocr)
      entry.score +=
        ocr.pages.reduce(
          (score, p) =>
            score +
            (p.text.toLowerCase().match(/[a-z0-9]{4,}/g) || []).filter((w) => words.has(w)).length,
          0,
        ) / 100;
    entry.fingerprint = fingerprint;
    entry.ocr = ocr;
  }
  ranked.sort((a, b) => b.score - a.score || a.path.localeCompare(b.path));
  for (const entry of ranked.filter((e) => e.fingerprint).slice(0, 8)) {
    try {
      const ocr = entry.ocr || (await extract(await confined(root, entry.path), helper));
      if (!entry.ocr) await atomicJSON(path.join(cacheDir, entry.fingerprint + '.json'), ocr);
      candidates.push({
        path: entry.path,
        pageCount: ocr.pageCount,
        text: ocr.pages
          .map((p) => p.text)
          .join('\n')
          .slice(0, 6000),
      });
    } catch {
      candidates.push({ path: entry.path, text: 'Text unavailable; do not infer its contents.' });
    }
  }
  if (duplicate)
    candidates.unshift({ path: duplicate, identicalBytes: true, text: 'Identical PDF bytes.' });
  return {
    folders: [...folders].slice(0, 300),
    candidates,
    duplicate,
    limited: limited || folders.size > 300,
    filesConsidered: files.length,
  };
}
