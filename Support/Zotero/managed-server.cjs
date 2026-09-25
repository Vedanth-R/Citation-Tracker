'use strict';
// Lifecycle adapter; upstream translation-server source remains unmodified.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { createRequire } = require('node:module');
const serverRoot = process.argv[2];
const readyFile = process.argv[3];
const parentPID = Number(process.argv[4]);
const token = process.env.CITEKIT_ZOTERO_TOKEN;
if (!serverRoot || !readyFile || !parentPID || !token) process.exit(2);
const serverRequire = createRequire(path.join(serverRoot, 'package.json'));
const Koa = serverRequire('koa');
const originalListen = Koa.prototype.listen;
let server;
let stopping = false;
function shutdown() {
    if (stopping) return;
    stopping = true;
    if (server) server.close(() => process.exit(0));
    else process.exit(0);
    setTimeout(() => process.exit(0), 1500).unref();
}
function authorized(header) {
    const expected = Buffer.from('Bearer ' + token);
    const supplied = Buffer.from(header || '');
    return supplied.length === expected.length && crypto.timingSafeEqual(supplied, expected);
}
Koa.prototype.listen = function () {
    this.middleware.unshift(async (ctx, next) => {
        if (!authorized(ctx.get('authorization'))) { ctx.status = 401; return; }
        if (ctx.path === '/citekit-health' && ctx.method === 'GET') {
            ctx.body = { service: 'CiteKit Zotero', pid: process.pid }; return;
        }
        await next();
    });
    // Use an OS-assigned port; never attach to or stop someone else's server.
    server = originalListen.call(this, 0, '127.0.0.1');
    server.once('listening', () => {
        fs.writeFileSync(readyFile, JSON.stringify({ port: server.address().port, pid: process.pid }), { mode: 0o600 });
    });
    return server;
};
process.stdin.resume();
process.stdin.on('end', shutdown);
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
setInterval(() => {
    try { process.kill(parentPID, 0); } catch { shutdown(); }
}, 1000).unref();
require(path.join(serverRoot, 'src/server.js'));
