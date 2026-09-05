import fs from 'node:fs/promises';
import path from 'node:path';
import { createHash, randomUUID } from 'node:crypto';
export const hash = (data) => createHash('sha256').update(data).digest('hex');
export async function readJSON(file) {
  return JSON.parse(await fs.readFile(file, 'utf8'));
}
export async function exists(file) {
  try {
    await fs.lstat(file);
    return true;
  } catch (e) {
    if (e.code === 'ENOENT') return false;
    throw e;
  }
}
export async function atomicJSON(file, value) {
  const temp = file + '.' + randomUUID() + '.partial';
  const handle = await fs.open(temp, 'wx', 0o600);
  try {
    await handle.writeFile(JSON.stringify(value, null, 2));
    await handle.sync();
  } finally {
    await handle.close();
  }
  try {
    await fs.rename(temp, file);
    await syncDir(path.dirname(file));
  } finally {
    await fs.rm(temp, { force: true });
  }
}
export async function syncDir(dir) {
  const h = await fs.open(dir, 'r');
  try {
    await h.sync();
  } finally {
    await h.close();
  }
}
export function validRelative(relative, { pdf = false } = {}) {
  if (
    typeof relative !== 'string' ||
    relative.length > 800 ||
    /[\x00-\x1f\x7f\\:]/.test(relative) ||
    path.isAbsolute(relative)
  )
    throw new Error('Invalid filing path.');
  const parts = relative.split('/');
  if (
    parts.length > 8 ||
    parts.some(
      (p) => !p || p === '.' || p === '..' || p.startsWith('.') || p.length > 180 || p.trim() !== p,
    )
  )
    throw new Error('Invalid filing path.');
  if (pdf && !relative.toLowerCase().endsWith('.pdf'))
    throw new Error('A PDF filename is required.');
  return parts;
}
export async function confined(root, relative, createParents = false) {
  const parts = validRelative(relative),
    canonical = await fs.realpath(root);
  if (canonical !== root)
    throw new Error('The filing folder has moved or become a link. Choose it again.');
  let current = root;
  for (let i = 0; i < parts.length; i++) {
    current = path.join(current, parts[i]);
    if (await exists(current)) {
      const stat = await fs.lstat(current);
      if (stat.isSymbolicLink() || (i < parts.length - 1 && !stat.isDirectory()))
        throw new Error('Filing through symbolic links is not allowed.');
    } else if (createParents && i < parts.length - 1) {
      await fs.mkdir(current);
    }
  }
  return current;
}
export async function publishBytes(source, target, expected) {
  const bytes = await fs.readFile(source);
  if (hash(bytes) !== expected) throw new Error('Saved PDF integrity check failed.');
  const temp = path.join(path.dirname(target), '.' + randomUUID() + '.partial');
  const h = await fs.open(temp, 'wx', 0o600);
  try {
    await h.writeFile(bytes);
    await h.sync();
  } finally {
    await h.close();
  }
  try {
    await fs.link(temp, target);
    await syncDir(path.dirname(target));
  } finally {
    await fs.rm(temp, { force: true });
  }
}
export async function removeIfSame(file, expected) {
  if (!(await exists(file))) return;
  const st = await fs.lstat(file);
  if (!st.isFile() || st.isSymbolicLink()) return;
  if (hash(await fs.readFile(file)) === expected) {
    await fs.unlink(file);
    await syncDir(path.dirname(file));
  }
}
