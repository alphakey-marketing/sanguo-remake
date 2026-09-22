import { WebSocketServer, type WebSocket } from 'ws';
import { World, W, H } from './world.ts';
import { addBots, thinkBots } from './bots.ts';
import type { C2S, S2C } from './protocol.ts';

const PORT = Number(process.env.PORT ?? 8765);
const world = new World();
world.initMobs();
const botIds = addBots(world, 30);
const wss = new WebSocketServer({ host: '127.0.0.1', port: PORT });   // 只綁本機
const conns = new Map<WebSocket, number>();
const send = (ws: WebSocket, m: S2C) => ws.readyState === 1 && ws.send(JSON.stringify(m));

wss.on('connection', ws => {
  ws.on('message', raw => {
    let m: C2S;
    try { m = JSON.parse(String(raw)); } catch { return; }
    if (m.t === 'join' && !conns.has(ws)) {
      const e = world.spawnPlayer(String(m.name ?? '').slice(0, 8) || '無名');
      conns.set(ws, e.id);
      send(ws, { t: 'welcome', id: e.id, w: W, h: H, walls: [...world.blocked] });
    } else if (m.t === 'move' && conns.has(ws)) {
      world.setTarget(conns.get(ws)!, m.x | 0, m.y | 0);   // server 驗證 isFree，一 tick 一格
    } else if (m.t === 'attack' && conns.has(ws)) {
      world.attack(conns.get(ws)!, m.target | 0);
    } else if (m.t === 'chat' && conns.has(ws)) {
      world.chat(conns.get(ws)!, String(m.text ?? ''));
    } else if (m.t === 'rest' && conns.has(ws)) {
      world.rest(conns.get(ws)!);
    } else if (m.t === 'buy' && conns.has(ws)) {
      world.buy(conns.get(ws)!, m.item | 0, m.n | 0);
    } else if (m.t === 'sell' && conns.has(ws)) {
      world.sell(conns.get(ws)!, m.item | 0, m.n | 0);
    }
  });
  ws.on('close', () => { const id = conns.get(ws); if (id) world.remove(id); conns.delete(ws); });
});

setInterval(() => {
  thinkBots(world, botIds);
  world.step();
  for (const [ws, id] of conns) {
    const view = world.view(id), seen = new Set(view.map(v => v.id));
    send(ws, { t: 'snap', tick: world.tick, ents: view });
    const ev = world.events.filter(e => e.k === 'msg' ? e.dst === id : ('src' in e && seen.has(e.src)) || seen.has(e.dst));
    for (const c of world.chats)
      if (seen.has(c.id))
        send(ws, { t: 'chat', id: c.id, name: c.name, text: c.text });
    if (ev.length) send(ws, { t: 'ev', ev });
    const me = world.ents.get(id);
    if (me?.ch && (world.tick % 5 === 0 || ev.length)) send(ws, { t: 'me', ch: me.ch });
  }
  world.events.length = 0; world.chats.length = 0;
}, 100);   // 10 Hz

console.log(`sanguo-remake server: ws://127.0.0.1:${PORT}`);
