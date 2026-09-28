'use strict';
const express = require('express');
const { createEngine, createMiddleware } = require('../../npm/http-server');

async function main() {
  const engine = await createEngine({ root: process.env.HS_ROOT || '.', handle_error: false, cache_control: 'no-cache' });
  const app = express();
  // The mounted middleware receives req.url after Express strips /static.
  app.use('/static', createMiddleware(engine));
  app.get('/api/health', (_req, res) => res.json({ source: 'Express', ok: true }));
  app.get('/static/*path', (_req, res) => res.send('dynamic Express fallback'));
  app.get('/__close', async (_req, res, next) => {
    try { await engine.close(); res.send('closed'); } catch (error) { next(error); }
  });
  app.get('/__shutdown', (_req, res) => {
    res.end('stopping');
    server.close(async () => { await engine.close(); });
    server.closeIdleConnections();
  });
  app.use((error, _req, res, _next) => {
    if (res.headersSent) { res.destroy(error); return; }
    res.status(500).send(error.code || 'ERROR');
  });
  const server = app.listen(0, '127.0.0.1', () => console.log('LISTENING', server.address().port));
}
main().catch(error => { console.error(error); process.exitCode = 1; });
