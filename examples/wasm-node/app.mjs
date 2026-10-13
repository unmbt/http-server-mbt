import http from 'node:http';
import { once } from 'node:events';
import { pathToFileURL } from 'node:url';
import { createEngine } from './index.mjs';

export async function serve(config = {}, { port = 8080, address = '127.0.0.1' } = {}) {
  const engine = await createEngine(config);
  const server = http.createServer(async (req, res) => {
    const controller = new AbortController();
    const abort = () => { if (!res.writableFinished) controller.abort(); };
    req.once('aborted', abort); res.once('close', abort);
    let body;
    try {
      const headers = [];
      for (let i = 0; i < req.rawHeaders.length; i += 2) headers.push([req.rawHeaders[i], req.rawHeaders[i + 1]]);
      const result = await engine.handle({method:req.method,target:req.url,headers,signal:controller.signal});
      if (result.kind === 'next') { res.writeHead(404); res.end('Not found'); return; }
      body = result.body;
      let prepared = false;
      const prepare = () => {
        if (prepared) return;
        prepared = true; res.statusCode = result.status;
        for (const [name,value] of result.headers) res.appendHeader(name,value);
      };
      for await (const bytes of body) {
        prepare();
        if (!res.write(bytes)) await once(res, 'drain', {signal:controller.signal});
      }
      prepare(); res.end();
    } catch (error) {
      if (res.headersSent || res.destroyed) res.destroy(error);
      else {
        const status = {HS_FILE_CHANGED:409,HS_FORBIDDEN:403,HS_INVALID_REQUEST:400,HS_OVERLOADED:503,HS_CLOSED:503}[error.code] || 500;
        res.writeHead(status, {'Content-Type':'text/plain; charset=utf-8'}); res.end(error.code || 'HS_IO');
      }
    } finally { body?.destroy(); req.removeListener('aborted',abort); res.removeListener('close',abort); }
  });
  try { server.listen(port,address); await once(server,'listening'); }
  catch (error) { await engine.close(); throw error; }
  let closing;
  const close = () => closing ||= (async () => {
    const stopped = new Promise((resolve,reject) => server.close(error => error ? reject(error) : resolve()));
    await engine.close(); server.closeAllConnections(); await stopped;
  })();
  return {server,engine,close};
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const config = JSON.parse(process.env.HS_CONFIG || '{}');
    config.root = process.env.HS_ROOT || config.root || '.';
    const running = await serve(config,{port:Number(process.env.PORT || '8080')});
    console.log(`LISTENING http://127.0.0.1:${running.server.address().port}`);
    const stop = () => running.close().catch(error => {console.error(error);process.exitCode=1;});
    process.once('SIGINT',stop); process.once('SIGTERM',stop);
  } catch (error) { console.error(error); process.exitCode = 1; }
}
