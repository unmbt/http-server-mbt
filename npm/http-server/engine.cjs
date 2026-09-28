'use strict';
const { Readable } = require('node:stream');

module.exports = function engineApi(binding) {
  const closedError = () => Object.assign(new Error('Engine closed'), { code: 'HS_CLOSED' });
  const abortError = () => Object.assign(new Error('Request aborted'), { name: 'AbortError', code: 'HS_CANCELLED' });
  function operation(start, signal) {
    if (signal?.aborted) return Promise.reject(abortError());
    const { promise, token } = start();
    const cancel = () => { if (token) binding._cancel(token); };
    signal?.addEventListener('abort', cancel, { once: true });
    if (signal?.aborted) cancel();
    return promise.catch(error => {
      if (signal?.aborted) throw abortError();
      throw error;
    }).finally(() => {
      signal?.removeEventListener('abort', cancel);
      if (token) binding._release(token);
    });
  }
  function headersArray(headers = []) {
    if (Array.isArray(headers)) return headers.map(pair => {
      if (!Array.isArray(pair) || pair.length !== 2 || pair.some(v => typeof v !== 'string')) {
        throw new TypeError('Headers must contain string pairs');
      }
      return pair;
    });
    return Object.entries(headers).flatMap(([key, value]) =>
      (Array.isArray(value) ? value : [value]).map(v => [key, String(v)]));
  }
  class Body extends Readable {
    constructor(engine, raw, signal) {
      super({ highWaterMark: 65536, autoDestroy: true });
      this.engine = engine;
      this.raw = raw;
      this.reading = false;
      this.signal = signal;
      this.abort = () => this.destroy(abortError());
      // A response can be abandoned before a caller installs a stream handler.
      // Keep its error observable to iterators without an unhandled event.
      this.on('error', () => {});
      signal?.addEventListener('abort', this.abort, { once: true });
      engine.bodies.add(this);
      if (signal?.aborted) this.abort();
    }
    _read() {
      if (this.reading || this.destroyed || !this.raw) return;
      this.reading = true;
      this.engine.track(operation(() => binding._read(this.raw), this.signal)).then(bytes => {
        this.reading = false;
        if (!this.destroyed) this.push(bytes);
      }, error => {
        this.reading = false;
        if (!this.destroyed) this.destroy(error);
      });
    }
    _destroy(error, callback) {
      this.signal?.removeEventListener('abort', this.abort);
      if (this.raw) { binding._release(this.raw); this.raw = null; }
      this.engine.bodies.delete(this);
      callback(error);
    }
  }
  class StaticEngine {
    constructor(raw) {
      this.raw = raw;
      this.closing = false;
      this.closed = null;
      this.pending = new Set();
      this.bodies = new Set();
    }
    track(promise) {
      this.pending.add(promise);
      promise.then(() => this.pending.delete(promise), () => this.pending.delete(promise));
      return promise;
    }
    async handle(request) {
      if (this.closing) throw closedError();
      if (!request || typeof request.method !== 'string' || typeof request.target !== 'string') {
        throw new TypeError('Request requires method and raw target strings');
      }
      const result = await this.track(operation(() => binding._submit(
        this.raw, request.method, request.target, headersArray(request.headers)
      ), request.signal));
      if (result.kind === 'next') return result;
      if (this.closing || request.signal?.aborted) {
        binding._release(result.response);
        throw this.closing ? closedError() : abortError();
      }
      return { kind: 'handled', status: result.status, headers: result.headers,
        contentLength: result.contentLength, body: new Body(this, result.response, request.signal) };
    }
    close() {
      if (this.closed) return this.closed;
      this.closing = true;
      for (const body of this.bodies) body.destroy(closedError());
      this.closed = (async () => {
        await operation(() => binding._closeEngine(this.raw));
        await Promise.allSettled([...this.pending]);
        binding._release(this.raw);
        this.raw = null;
      })();
      return this.closed;
    }
  }
  async function createEngine(config = {}) {
    const json = typeof config === 'string' ? config : JSON.stringify(config);
    return new StaticEngine(await operation(() => binding._createEngine(json)));
  }
  function createMiddleware(engine) {
    if (!(engine instanceof StaticEngine)) throw new TypeError('Expected StaticEngine');
    return function staticMiddleware(req, res, next) {
      const controller = new AbortController();
      const abort = () => { if (!res.writableFinished) controller.abort(); };
      req.once('aborted', abort);
      res.once('close', abort);
      const cleanup = () => { req.removeListener('aborted', abort); res.removeListener('close', abort); };
      const headers = [];
      for (let i = 0; i < req.rawHeaders.length; i += 2) headers.push([req.rawHeaders[i], req.rawHeaders[i + 1]]);
      (async () => {
        let body;
        try {
          const result = await engine.handle({ method: req.method, target: req.url, headers, signal: controller.signal });
          if (result.kind === 'next') { cleanup(); next(); return; }
          body = result.body;
          let prepared = false;
          const prepareHeaders = () => {
            if (prepared) return;
            prepared = true;
            res.statusCode = result.status;
            for (const [name, value] of result.headers) res.appendHeader(name, value);
          };
          for await (const bytes of body) {
            prepareHeaders();
            if (!res.write(bytes)) await new Promise((resolve, reject) => {
              const drain = () => { detach(); resolve(); };
              const closed = () => { detach(); reject(abortError()); };
              const detach = () => { res.removeListener('drain', drain); res.removeListener('close', closed); };
              res.once('drain', drain); res.once('close', closed);
              if (res.destroyed) closed();
            });
          }
          prepareHeaders();
          res.end();
        } catch (error) {
          if (res.headersSent || res.destroyed) res.destroy(error);
          else next(error);
        } finally { body?.destroy(); cleanup(); }
      })();
    };
  }
  return { StaticEngine, createEngine, createMiddleware };
};
