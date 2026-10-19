// A static server that behaves like GitHub Pages serving a project site: everything lives under the base
// path, anything outside it is a 404, /dir without a slash redirects to /dir/, and a missing page gets
// 404.html with a 404 status. Text is gzip-compressed when the client accepts it, as Pages does.
import http from 'node:http';
import zlib from 'node:zlib';
import { readFile, stat } from 'node:fs/promises';
import { extname, join, normalize, sep } from 'node:path';

const TYPES = {
  '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png', '.woff2': 'font/woff2',
  '.xml': 'application/xml', '.txt': 'text/plain; charset=utf-8',
};
const COMPRESSIBLE = new Set(['.html', '.css', '.js', '.json', '.svg', '.xml', '.txt']);

export async function serve(dir, base /* '/DNDReader' or '/' */) {
  const prefix = base === '/' ? '/' : base.replace(/\/?$/, '/');
  const send = async (req, res, status, file, extra = {}) => {
    const ext = extname(file);
    let body = await readFile(file);
    const headers = { 'content-type': TYPES[ext] ?? 'application/octet-stream', 'cache-control': 'no-store', ...extra };
    if (COMPRESSIBLE.has(ext) && /\bgzip\b/.test(req.headers['accept-encoding'] ?? '')) {
      body = zlib.gzipSync(body);
      headers['content-encoding'] = 'gzip';
    }
    headers['content-length'] = body.length;
    res.writeHead(status, headers);
    res.end(req.method === 'HEAD' ? undefined : body);
  };
  const notFound = async (req, res) => {
    try { await send(req, res, 404, join(dir, '404.html')); } catch { res.writeHead(404); res.end('not found'); }
  };

  const server = http.createServer(async (req, res) => {
    try {
      const url = new URL(req.url, 'http://x');
      const pathname = decodeURIComponent(url.pathname);
      if (!pathname.startsWith(prefix)) {
        if (prefix !== '/' && pathname + '/' === prefix) { res.writeHead(301, { location: prefix }); return res.end(); }
        return notFound(req, res);
      }
      let rel = pathname.slice(prefix.length);
      const wantsDir = rel === '' || rel.endsWith('/');
      const target = normalize(join(dir, wantsDir ? join(rel, 'index.html') : rel));
      if (target !== dir && !target.startsWith(dir + sep)) return notFound(req, res);
      try {
        const s = await stat(target);
        if (s.isFile()) return send(req, res, 200, target);
      } catch {}
      if (!wantsDir) {
        try {
          if ((await stat(join(dir, rel, 'index.html'))).isFile()) { res.writeHead(301, { location: prefix + rel + '/' }); return res.end(); }
        } catch {}
      }
      return notFound(req, res);
    } catch {
      res.writeHead(500); res.end('error');
    }
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const { port } = server.address();
  return { origin: `http://127.0.0.1:${port}`, prefix, close: () => new Promise((r) => server.close(r)) };
}
