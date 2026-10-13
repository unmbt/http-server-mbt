import path from 'node:path';
import { Readable } from 'node:stream';
import { loadEngineModule } from './loader.mjs';
import { FileHost, fault, cancelled, ioError } from './host.mjs';

function decode(text) {
  const value = JSON.parse(text);
  if (value.kind === 'error') throw fault(`HS_${value.code}`, value.message);
  return value;
}
function headersArray(headers = []) {
  const pairs = Array.isArray(headers) ? headers : Object.entries(headers).flatMap(([k, v]) => (Array.isArray(v) ? v : [v]).map(s => [k, s]));
  if (pairs.some(pair => !Array.isArray(pair) || pair.length !== 2 || pair.some(v => typeof v !== 'string'))) throw fault('HS_INVALID_REQUEST', 'Headers must be string pairs');
  return pairs;
}

class Body extends Readable {
  constructor(engine, state, description) {
    super({ highWaterMark: state.chunkSize, autoDestroy: true });
    this.engine = engine; this.state = state; this.description = description;
    this.cursor = 0n; this.reading = false;
    this.on('error', () => {});
    this.done = new Promise(resolve => this.once('close', resolve));
    state.body = this;
  }
  _read() {
    if (this.reading || this.destroyed) return;
    this.reading = true;
    const { engine, state, description: d } = this;
    state.work = (async () => {
      engine.ensure(state);
      let bytes;
      if (d.type === 'file') {
        const remaining = BigInt(d.length) - this.cursor;
        const count = Number(remaining < BigInt(state.chunkSize) ? remaining : BigInt(state.chunkSize));
        // Check once more at EOF, including zero-length files.
        if (!count) { await engine.host.check(state, d.token); bytes = Buffer.alloc(0); }
        else bytes = await engine.host.read(state, d.token, BigInt(d.offset) + this.cursor, count);
      } else {
        const values = decode(engine.wasm.take_chunk(state.id, Number(this.cursor), state.chunkSize));
        bytes = Buffer.from(values);
      }
      engine.ensure(state);
      this.cursor += BigInt(bytes.length);
      return bytes;
    })();
    state.work.then(bytes => {
      this.reading = false;
      if (!this.destroyed) this.push(bytes.length ? bytes : null);
    }, error => { this.reading = false; this.destroy(error); });
  }
  _destroy(error, callback) {
    this.state.cancelled = true;
    this.state.reason ||= error || cancelled();
    Promise.resolve(this.state.work).catch(() => {}).then(() => this.engine.dispose(this.state)).then(() => callback(error), callback);
  }
}

export class StaticEngine {
  constructor(wasm, host, config, limits) {
    this.wasm = wasm; this.host = host; this.config = config; this.limits = limits;
    this.states = new Map(); this.pending = new Set(); this.nextId = 1; this.closing = false; this.closed = null;
  }
  ensure(state) {
    if (state.cancelled || this.closing) throw state.reason || fault('HS_CLOSED');
  }
  dispose(state) {
    if (state.disposing) return state.disposing;
    state.disposing = (async () => {
      state.signal?.removeEventListener('abort', state.abort);
      const closed = await Promise.allSettled([...state.tokens].map(token => this.host.closeToken(token)));
      this.host.release('body', state.bodyCharge);
      this.host.release('directory', state.directoryCharge);
      state.bodyCharge = state.directoryCharge = 0;
      this.wasm.release(state.id); this.states.delete(state.id);
      const failure = closed.find(r => r.status === 'rejected');
      if (failure) throw failure.reason;
    })();
    return state.disposing;
  }
  async plan(state, request) {
    let step = decode(this.wasm.begin_request(state.id, JSON.stringify({ method: request.method, target: request.target, headers: headersArray(request.headers) })));
    while (['open', 'prefix', 'list'].includes(step.kind)) {
      this.ensure(state);
      let result;
      if (step.kind === 'open') result = await this.host.open(state, step.path);
      else if (step.kind === 'prefix') {
        const file = this.host.lease(state, step.token);
        const count = Number(file.stat.size < BigInt(step.count) ? file.stat.size : BigInt(step.count));
        result = [...await this.host.read(state, step.token, 0n, count)];
      } else {
        const charge = request.target.length * 32 + 16384;
        this.host.reserve('directory', charge); state.directoryCharge += charge;
        result = await this.host.list(state, step.path);
      }
      this.ensure(state);
      step = decode(this.wasm.complete(state.id, step.serial, JSON.stringify(result)));
    }
    this.ensure(state);
    if (step.kind === 'next') { await this.dispose(state); return { kind: 'next' }; }
    if (step.kind !== 'handled') throw fault('HS_IO', 'Unexpected Wasm response');
    const token = step.body.type === 'file' ? step.body.token : null;
    for (const t of [...state.tokens]) {
      await this.host.check(state, t);
      if (t !== token) await this.host.closeToken(t);
    }
    if (step.body.type !== 'listing') { this.host.release('directory', state.directoryCharge); state.directoryCharge = 0; }
    // Generated JSON byte chunks coexist with Wasm arrays, strings and Buffer.
    // Charge conservatively and shrink chunks to fit a small configured budget.
    const factor = ['bytes', 'listing'].includes(step.body.type) ? 32 : 3;
    state.chunkSize = Math.min(this.limits.body_block_bytes, Math.floor(this.limits.body_buffer_bytes / factor));
    const charge = state.chunkSize * factor;
    this.host.reserve('body', charge);
    state.bodyCharge = charge;
    this.ensure(state);
    return { kind: 'handled', status: step.status, headers: step.headers,
      contentLength: step.body.length === null ? null : BigInt(step.body.length), body: new Body(this, state, step.body) };
  }
  handle(request) {
    if (this.closing) return Promise.reject(fault('HS_CLOSED'));
    if (!request || typeof request.method !== 'string' || typeof request.target !== 'string') return Promise.reject(fault('HS_INVALID_REQUEST', 'method and raw target are required'));
    if (request.signal?.aborted) return Promise.reject(cancelled());
    if (this.states.size >= this.limits.connections || this.nextId > 2147483647) return Promise.reject(fault('HS_OVERLOADED'));
    const state = { id: this.nextId++, tokens: new Set(), cancelled: false, signal: request.signal, bodyCharge: 0, directoryCharge: 0 };
    state.abort = () => { state.cancelled = true; state.reason = cancelled(); state.body?.destroy(state.reason); };
    state.signal?.addEventListener('abort', state.abort, { once: true });
    if (state.signal?.aborted) state.abort();
    this.states.set(state.id, state);
    state.work = this.plan(state, request);
    const accepted = state.work.catch(async error => { await this.dispose(state); throw ioError(error); });
    this.pending.add(accepted);
    accepted.then(() => this.pending.delete(accepted), () => this.pending.delete(accepted));
    return accepted;
  }
  close() {
    if (this.closed) return this.closed;
    this.closing = true; this.host.stop();
    const states = [...this.states.values()];
    for (const state of states) {
      state.cancelled = true; state.reason = fault('HS_CLOSED'); state.body?.destroy(state.reason);
    }
    this.closed = (async () => {
      await Promise.allSettled(states.map(s => s.work));
      await Promise.all(states.map(s => this.dispose(s)));
      await Promise.all(states.map(s => s.body?.done));
      await Promise.allSettled([...this.pending]);
    })();
    return this.closed;
  }
}

export async function createEngine(config = {}) {
  config = typeof config === 'string' ? JSON.parse(config) : config;
  if (!config || typeof config !== 'object' || Array.isArray(config)) throw fault('HS_INVALID_REQUEST', 'Expected a configuration object');
  config = { ...config, root: path.resolve(config.root ?? '.') };
  const wasm = await loadEngineModule();
  const parsed = decode(wasm.configure(JSON.stringify(config)));
  const host = await FileHost.open(config.root, parsed.limits);
  if (parsed.fallback) {
    const state = {tokens:new Set(), cancelled:false};
    try {
      const file = await host.open(state, path.join(config.root, parsed.fallback));
      if (!file || file.type !== 1) throw fault('HS_INVALID_REQUEST', 'Fallback must be a readable regular file');
    } finally { await Promise.all([...state.tokens].map(t => host.closeToken(t))); }
  }
  return new StaticEngine(wasm, host, config, parsed.limits);
}
