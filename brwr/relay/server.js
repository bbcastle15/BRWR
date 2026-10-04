'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { WebSocketServer, WebSocket } = require('ws');

const PORT = Number(process.env.PORT || 10000);
const WEB_ROOT = path.resolve(__dirname, '..', 'output', 'web');
const MAX_PAYLOAD = 16 * 1024 * 1024;
const rooms = new Map();

const mime = new Map([
  ['.html', 'text/html; charset=utf-8'],
  ['.js', 'application/javascript; charset=utf-8'],
  ['.wasm', 'application/wasm'],
  ['.pck', 'application/octet-stream'],
  ['.png', 'image/png'],
  ['.jpg', 'image/jpeg'],
  ['.jpeg', 'image/jpeg'],
  ['.svg', 'image/svg+xml'],
  ['.ico', 'image/x-icon'],
  ['.json', 'application/json; charset=utf-8'],
]);

function json(ws, value) {
  if (ws && ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(value));
}

function error(ws, message) {
  json(ws, { type: 'error', message });
}

function makeCode() {
  for (let i = 0; i < 20; i += 1) {
    const code = crypto.randomBytes(6).toString('hex').toUpperCase();
    if (!rooms.has(code)) return code;
  }
  throw new Error('Unable to allocate room code');
}

function seatsFor(room) {
  const values = [0];
  for (const client of room.clients.values()) values.push(client.seat);
  return values.sort((a, b) => a - b);
}

function nextSeat(room) {
  const used = new Set(seatsFor(room));
  for (let seat = 1; seat < room.count; seat += 1) {
    if (!used.has(seat)) return seat;
  }
  return -1;
}

function closeRoom(room, reason = "La sala è stata chiusa dall'host.") {
  if (!room) return;
  rooms.delete(room.code);
  for (const client of room.clients.values()) {
    json(client.ws, { type: 'room_closed', message: reason });
    try { client.ws.close(4000, 'room closed'); } catch (_) {}
  }
  room.clients.clear();
}

function handleCreate(ws, message) {
  if (ws.room) return error(ws, 'Connessione già associata a una sala.');
  const count = Number(message.count);
  const version = String(message.version || '');
  const protocol = String(message.protocol || '');
  if (!Number.isInteger(count) || count < 2 || count > 6) return error(ws, 'Numero giocatori non valido.');
  if (!version || version.length > 128) return error(ws, 'Versione client non valida.');
  if (!protocol || protocol.length > 64) return error(ws, 'Protocollo client non valido.');

  const code = makeCode();
  const room = {
    code,
    count,
    version,
    protocol,
    host: ws,
    clients: new Map(),
    nextPeerId: 2,
    started: false,
    createdAt: Date.now(),
  };
  rooms.set(code, room);
  ws.room = room;
  ws.role = 'host';
  json(ws, { type: 'created', code, count });
  console.log(`[room ${code}] created ${count}p`);
}

function handleJoin(ws, message) {
  if (ws.room) return error(ws, 'Connessione già associata a una sala.');
  const code = String(message.code || '').trim().toUpperCase();
  const version = String(message.version || '');
  const protocol = String(message.protocol || '');
  const room = rooms.get(code);

  if (!room) return error(ws, 'Sala non trovata o già chiusa.');
  if (room.started) return error(ws, 'Partita già iniziata.');
  if (version !== room.version || protocol !== room.protocol) {
    return error(ws, "Versioni diverse: l'host deve ricreare la versione browser dopo le modifiche.");
  }
  if (room.clients.size >= room.count - 1) return error(ws, 'Sala completa.');

  const seat = nextSeat(room);
  if (seat < 0) return error(ws, 'Sala completa.');

  const peerId = String(room.nextPeerId++);
  const client = { ws, peerId, seat };
  room.clients.set(peerId, client);
  ws.room = room;
  ws.role = 'client';
  ws.peerId = peerId;

  json(ws, { type: 'joined', count: room.count, seat, seats: seatsFor(room) });
  json(room.host, { type: 'peer_joined', peer_id: peerId, seat });
  console.log(`[room ${code}] peer ${peerId} -> seat ${seat}`);
}

function handleGame(ws, message) {
  const room = ws.room;
  if (!room) return error(ws, 'Nessuna sala attiva.');
  const payload = String(message.payload || '');
  if (!payload || payload.length > MAX_PAYLOAD * 2) return error(ws, 'Pacchetto di gioco non valido.');

  if (ws.role === 'host') {
    const peerId = String(message.to || '');
    const client = room.clients.get(peerId);
    if (client) json(client.ws, { type: 'game', peer_id: 'host', payload });
  } else if (ws.role === 'client') {
    json(room.host, { type: 'game', peer_id: ws.peerId, payload });
  }
}

function handleMessage(ws, raw, isBinary) {
  if (isBinary) return error(ws, 'Il relay BRWR accetta solo envelope JSON testuali.');
  let message;
  try {
    message = JSON.parse(raw.toString('utf8'));
  } catch (_) {
    return error(ws, 'Messaggio JSON non valido.');
  }
  if (!message || typeof message !== 'object') return error(ws, 'Messaggio non valido.');

  switch (String(message.type || '')) {
    case 'create': return handleCreate(ws, message);
    case 'join': return handleJoin(ws, message);
    case 'game': return handleGame(ws, message);
    case 'lock':
      if (ws.role === 'host' && ws.room) ws.room.started = true;
      return;
    case 'ping':
      return json(ws, { type: 'pong', now: Date.now() });
    default:
      return error(ws, 'Tipo di messaggio sconosciuto.');
  }
}

function cleanupSocket(ws) {
  const room = ws.room;
  if (!room) return;

  if (ws.role === 'host') {
    console.log(`[room ${room.code}] host disconnected`);
    closeRoom(room);
    return;
  }

  if (ws.role === 'client') {
    room.clients.delete(ws.peerId);
    json(room.host, { type: 'peer_left', peer_id: ws.peerId });
    console.log(`[room ${room.code}] peer ${ws.peerId} disconnected`);
  }
  ws.room = null;
}

function safeStaticPath(urlPath) {
  const decoded = decodeURIComponent(urlPath.split('?')[0]);
  const rel = decoded === '/' ? 'index.html' : decoded.replace(/^\/+/, '');
  if (rel.includes('\0')) return null;
  const absolute = path.resolve(WEB_ROOT, rel);
  if (!absolute.startsWith(WEB_ROOT + path.sep) && absolute !== path.join(WEB_ROOT, 'index.html')) return null;
  return absolute;
}

function serveStatic(req, res) {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
    res.end(JSON.stringify({ ok: true, rooms: rooms.size }));
    return;
  }

  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.writeHead(405, { Allow: 'GET, HEAD' });
    res.end();
    return;
  }

  let file;
  try { file = safeStaticPath(req.url || '/'); }
  catch (_) { file = null; }
  if (!file) {
    res.writeHead(400);
    res.end();
    return;
  }

  if (!fs.existsSync(file) || !fs.statSync(file).isFile()) {
    res.writeHead(503, { 'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'no-store' });
    res.end('BRWR browser build non presente in output/web. Esegui tools/build_web_render.ps1 e pubblica il risultato.');
    return;
  }

  const acceptsGzip = String(req.headers['accept-encoding'] || '').includes('gzip');
  const gzipFile = file + '.gz';
  const useGzip = acceptsGzip && fs.existsSync(gzipFile);
  const served = useGzip ? gzipFile : file;
  const ext = path.extname(file).toLowerCase();
  const stat = fs.statSync(served);
  const headers = {
    'Content-Type': mime.get(ext) || 'application/octet-stream',
    'Content-Length': stat.size,
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
    'Referrer-Policy': 'no-referrer',
  };
  if (useGzip) {
    headers['Content-Encoding'] = 'gzip';
    headers['Vary'] = 'Accept-Encoding';
  }
  res.writeHead(200, headers);
  if (req.method === 'HEAD') return res.end();
  fs.createReadStream(served).pipe(res);
}

const server = http.createServer(serveStatic);
const wss = new WebSocketServer({ noServer: true, maxPayload: MAX_PAYLOAD });

server.on('upgrade', (req, socket, head) => {
  const pathname = new URL(req.url || '/', 'http://localhost').pathname;
  if (pathname !== '/ws') {
    socket.write('HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n');
    socket.destroy();
    return;
  }
  wss.handleUpgrade(req, socket, head, ws => wss.emit('connection', ws, req));
});

wss.on('connection', ws => {
  ws.room = null;
  ws.role = '';
  ws.peerId = '';
  ws.on('message', (data, isBinary) => handleMessage(ws, data, isBinary));
  ws.on('close', () => cleanupSocket(ws));
  ws.on('error', err => console.error('websocket error:', err.message));
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`BRWR relay listening on 0.0.0.0:${PORT}`);
  console.log(`Static web root: ${WEB_ROOT}`);
});
