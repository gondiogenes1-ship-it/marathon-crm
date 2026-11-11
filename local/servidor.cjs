const http = require('node:http');
const fs = require('node:fs/promises');
const path = require('node:path');
const port = Number(process.argv[2] || 8123);
if (!Number.isInteger(port) || port < 1024 || port > 65535) throw Error('Puerto invalido.');
const root = path.resolve(__dirname, '..', 'public');
const types = {'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.css':'text/css; charset=utf-8','.json':'application/json; charset=utf-8','.svg':'image/svg+xml','.png':'image/png','.jpg':'image/jpeg','.jpeg':'image/jpeg','.ico':'image/x-icon','.woff2':'font/woff2'};
const inside = file => file.toLowerCase().startsWith(root.toLowerCase() + path.sep);
const server = http.createServer(async (req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Referrer-Policy', 'no-referrer');
  const send = (status, body, type='text/plain; charset=utf-8') => {
    res.writeHead(status, {'Content-Type':type, 'Content-Length':Buffer.byteLength(body)});
    res.end(req.method === 'HEAD' ? undefined : body);
  };
  if (!['127.0.0.1:'+port, 'localhost:'+port].includes(req.headers.host)) return send(403, 'Host no permitido.');
  if (!['GET','HEAD'].includes(req.method)) return send(405, 'Metodo no permitido.');
  try {
    const name = decodeURIComponent(new URL(req.url, 'http://127.0.0.1:'+port).pathname);
    if (name === '/__marathon_local_health') {
      const html = await fs.readFile(path.join(root, 'index.html'), 'utf8');
      return send(200, JSON.stringify({application:'marathon-crm-local', root:root.toLowerCase(), pid:process.pid, port, version:html.match(/v(\d+\.\d+\.\d+)/)?.[1] || 'local'}), 'application/json; charset=utf-8');
    }
    const candidate = path.resolve(root, '.' + (name === '/' ? '/index.html' : name));
    if (!inside(candidate)) return send(403, 'Ruta no permitida.');
    const file = await fs.realpath(candidate);
    if (!inside(file)) return send(403, 'Ruta no permitida.');
    const type = types[path.extname(file).toLowerCase()];
    if (!type || !(await fs.stat(file)).isFile()) return send(404, 'No encontrado.');
    send(200, await fs.readFile(file), type);
  } catch (e) {
    send(e instanceof URIError ? 400 : 404, 'No encontrado.');
  }
});
server.on('error', e => { console.error(e.code === 'EADDRINUSE' ? 'El puerto '+port+' ya esta ocupado.' : e.message); process.exitCode = 1; });
server.listen(port, '127.0.0.1', () => console.log('Marathon CRM local: http://127.0.0.1:'+port+'/'));
