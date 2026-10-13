// R-N10 / D-13 / T-029: asynchronous I/O only. Static decisions live in Wasm.
import * as fs from 'node:fs/promises';
import path from 'node:path';
import { constants } from 'node:fs';

export const fault = (code, message = code, cause) => Object.assign(new Error(message, { cause }), { code });
export const cancelled = () => Object.assign(fault('HS_CANCELLED', 'Request aborted'), { name: 'AbortError' });
export function ioError(error) {
  if (error?.code?.startsWith('HS_')) return error;
  if (['EACCES', 'EPERM', 'ELOOP'].includes(error?.code)) return fault('HS_FORBIDDEN', 'File access denied', error);
  return fault('HS_IO', 'File operation failed', error);
}

// Deployment controls directory structure. These checks reject links and normal
// traversal, but intentionally do not claim Native's hostile-rename isolation.
async function noLinks(absolute) {
  const parsed = path.parse(absolute);
  let current = parsed.root;
  for (const part of absolute.slice(parsed.root.length).split(path.sep).filter(Boolean)) {
    current = path.join(current, part);
    const stat = await fs.lstat(current);
    if (stat.isSymbolicLink()) throw fault('HS_FORBIDDEN', 'Symbolic links and junctions are not supported');
  }
}

export class FileHost {
  constructor(root, limits) {
    this.root = root; this.limits = limits;
    this.running = 0; this.queue = []; this.closing = false;
    this.tokens = new Map(); this.nextToken = 1;
    this.bodyBytes = 0; this.directoryBytes = 0;
  }
  static async open(root, limits) {
    root = path.resolve(root);
    await noLinks(root);
    if (!(await fs.stat(root)).isDirectory()) throw fault('HS_INVALID_REQUEST', 'root must be a directory');
    return new FileHost(root, limits);
  }
  reserve(kind, bytes) {
    const field = kind === 'body' ? 'bodyBytes' : 'directoryBytes';
    const limit = kind === 'body' ? this.limits.body_buffer_bytes : this.limits.directory_metadata_bytes;
    if (!Number.isSafeInteger(bytes) || bytes < 0 || bytes > limit - this[field]) throw fault('HS_OVERLOADED', `${kind} budget exhausted`);
    this[field] += bytes;
  }
  release(kind, bytes) { this[kind === 'body' ? 'bodyBytes' : 'directoryBytes'] -= bytes; }
  async run(state, action) {
    if (this.closing || state.cancelled) throw state.reason || fault('HS_CLOSED');
    if (this.running >= this.limits.file_workers) {
      if (this.queue.length >= this.limits.queued_operations) throw fault('HS_OVERLOADED', 'I/O queue full');
      await new Promise((resolve, reject) => this.queue.push({ resolve, reject, state }));
    } else this.running++;
    try {
      if (this.closing || state.cancelled) throw state.reason || fault('HS_CLOSED');
      return await action();
    } catch (error) { throw ioError(error); }
    finally {
      const next = this.queue.shift();
      if (next) next.resolve(); else this.running--;
    }
  }
  resolve(candidate) {
    const absolute = path.resolve(candidate);
    const relative = path.relative(this.root, absolute);
    if (relative === '..' || relative.startsWith(`..${path.sep}`) || path.isAbsolute(relative)) throw fault('HS_FORBIDDEN', 'Outside root');
    return absolute;
  }
  async open(state, candidate) {
    return this.run(state, async () => {
      let handle;
      try {
        const absolute = this.resolve(candidate);
        await noLinks(absolute);
        const named = await fs.stat(absolute, { bigint: true });
        if (named.isDirectory()) return { token: 0, type: 2, size: '0', mtime: String(named.mtimeNs / 1000000000n) };
        if (!named.isFile()) throw fault('HS_FORBIDDEN', 'Only regular files and directories are supported');
        handle = await fs.open(absolute, constants.O_RDONLY | (constants.O_NOFOLLOW || 0));
        const stat = await handle.stat({ bigint: true });
        if (!stat.isFile() || stat.dev !== named.dev || stat.ino !== named.ino) throw fault('HS_FILE_CHANGED');
        if (stat.size > 9223372036854775807n || stat.size < 0n) throw fault('HS_UNSUPPORTED', 'File size exceeds signed 64-bit range');
        if (this.nextToken > 2147483647) throw fault('HS_OVERLOADED', 'File token generation exhausted');
        const token = this.nextToken++;
        this.tokens.set(token, { handle, stat, state, absolute }); state.tokens.add(token); handle = null;
        return { token, type: 1, size: String(stat.size), mtime: String(stat.mtimeNs / 1000000000n) };
      } catch (error) {
        if (['ENOENT', 'ENOTDIR'].includes(error.code)) return null;
        throw error;
      } finally { if (handle) await handle.close(); }
    });
  }
  lease(state, token) {
    const value = this.tokens.get(token);
    if (!value || value.state !== state) throw fault('HS_CLOSED', 'Stale file token');
    return value;
  }
  async checkLease(value) {
    const now = await value.handle.stat({ bigint: true });
    const old = value.stat;
    // ctime may change solely due to rename/unlink. Such metadata changes do
    // not splice in a new file: the retained handle remains authoritative.
    if (now.dev !== old.dev || now.ino !== old.ino || now.size !== old.size || now.mtimeNs !== old.mtimeNs) throw fault('HS_FILE_CHANGED', 'Opened file changed');
    if (now.ctimeNs !== old.ctimeNs) {
      // Metadata-only rename/unlink of the opened inode is allowed. A same-name
      // identity still present with changed ctime invalidates even restored mtime.
      let named;
      try { named = await fs.stat(value.absolute, { bigint: true }); }
      catch (error) { if (!['ENOENT', 'ENOTDIR'].includes(error.code)) throw error; }
      if (named && named.dev === old.dev && named.ino === old.ino) throw fault('HS_FILE_CHANGED', 'Opened file metadata changed');
      value.stat = now;
    }
  }
  async check(state, token) { await this.run(state, () => this.checkLease(this.lease(state, token))); }
  async read(state, token, offset, count) {
    return this.run(state, async () => {
      const lease = this.lease(state, token);
      await this.checkLease(lease);
      const buffer = Buffer.allocUnsafe(count);
      // Node accepts bigint positions without truncating them through Number.
      const { bytesRead } = await lease.handle.read(buffer, 0, count, offset);
      await this.checkLease(lease);
      if (!bytesRead && count) throw fault('HS_FILE_CHANGED', 'Unexpected EOF');
      // A short view must not pin a full-size allocation in the Readable queue.
      return bytesRead === count ? buffer : Buffer.from(buffer.subarray(0, bytesRead));
    });
  }
  async list(state, candidate) {
    return this.run(state, async () => {
      const absolute = this.resolve(candidate);
      await noLinks(absolute);
      const dir = await fs.opendir(absolute, { bufferSize: 16 });
      const entries = [];
      for await (const entry of dir) {
        const charge = 512 + entry.name.length * 64;
        this.reserve('directory', charge); state.directoryCharge += charge;
        const child = path.join(absolute, entry.name);
        let stat;
        try { await noLinks(child); stat = await fs.stat(child, { bigint: true }); }
        catch (error) { if (['ENOENT', 'ENOTDIR'].includes(error.code)) continue; throw error; }
        if (!stat.isDirectory() && !stat.isFile()) throw fault('HS_FORBIDDEN');
        entries.push({name:entry.name, token:0,type:stat.isDirectory()?2:1,size:String(stat.isDirectory()?0n:stat.size),mtime:String(stat.mtimeNs/1000000000n)});
      }
      return entries;
    });
  }
  async closeToken(token) {
    const lease = this.tokens.get(token);
    if (!lease) return;
    this.tokens.delete(token); lease.state.tokens.delete(token);
    await lease.handle.close();
  }
  stop() {
    this.closing = true;
    for (const item of this.queue.splice(0)) item.reject(fault('HS_CLOSED'));
  }
}
