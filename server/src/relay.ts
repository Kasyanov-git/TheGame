/**
 * Godot Relay — WS-мост для клиента на Godot (Sprint 3, ТЗ п.4).
 *
 * Godot-сборка (web export) не использует бинарный Colyseus-клиент:
 * NetworkManager.gd ходит по «чистому» WebSocket в JSON-протокол, а relay
 * внутри сервера подключается к BattleRoom полноценным @colyseus/sdk
 * (loopback), т.е. Godot-игрок получает ВСЕ тот же авторитарный сервер,
 * репликацию схемы, hit validation и ботов — без дублирования логики.
 *
 * Протокол (JSON, компактные ключи):
 *   C→S: {"t":"in","s","th","st","dr","bo","f","ay","ap","px","pz","ry","vx","vz"}
 *   S→C: {"t":"ok","id"} | {"t":"st", ms, gt, pl[[…]], pr[[…]], pk[[…]]}
 *        | {"t":"ev","e","a"} | {"t":"rec","x","z","rotY"}
 */
import { WebSocketServer, WebSocket } from "ws";
import { URL } from "node:url";
import { ColyseusSDK } from "@colyseus/sdk";

const parse = (raw: string): any | null => {
  try { return JSON.parse(raw); } catch { return null; }
};

export class GodotRelay {
  private wss = new WebSocketServer({ noServer: true });

  constructor(private httpServer: import("node:http").Server, private colyseusUrl: string) {}

  listen(): void {
    this.httpServer.on("upgrade", (req, socket, head) => {
      const url = new URL(req.url ?? "/", "http://localhost");
      if (url.pathname !== "/godot-relay") return;      // не наше — пусть Colyseus
      this.wss.handleUpgrade(req, socket as any, head, (ws) => this.onClient(ws, url));
    });
  }

  private async onClient(ws: WebSocket, url: URL): Promise<void> {
    const name = url.searchParams.get("name") || "car";
    const weapon = url.searchParams.get("weapon") || "cannon";
    const client = new ColyseusSDK(this.colyseusUrl);
    let room: any = null;
    let open = true;
    try {
      room = await client.joinOrCreate("battle", { name, weapon });
    } catch (e: any) {
      ws.send(JSON.stringify({ t: "err", m: String(e?.message || e) }));
      ws.close();
      return;
    }
    if (!open) { room.leave(); return; }

    ws.send(JSON.stringify({ t: "ok", id: room.sessionId, weapon }));

    const input = room.input();

    room.onMessage("ev", (data: any) => ws.readyState === 1 && ws.send(JSON.stringify({ t: "ev", ...data })));
    room.onMessage("reconcile", (a: any) => ws.readyState === 1 && ws.send(JSON.stringify({ t: "rec", ...a })));

    room.onStateChange((state: any) => {
      if (ws.readyState !== 1) return;
      const pl: any[] = [];
      state.players.forEach((p: any, id: string) => pl.push([
        id, round(p.x), round(p.z), round(p.rotY), p.hp, p.score,
        p.isBot ? 1 : 0, p.weaponType === "mg" ? 1 : 0,
        round(p.shieldT), round(p.boostT), round(p.aimYaw), round(p.aimPitch),
        round(p.vx), round(p.vz),
      ]));
      const pr: any[] = [];
      state.projectiles.forEach((q: any, id: string) => pr.push([
        id, round(q.x), round(q.y), round(q.z), round(q.vx), round(q.vz),
      ]));
      const pk: any[] = [];
      state.pickups.forEach((k: any, id: string) => pk.push([
        Number(id), k.type, round(k.x), round(k.z), round(k.cd),
      ]));
      ws.send(JSON.stringify({
        t: "st", ms: state.matchState, gt: round(state.gameTimer),
        winner: state.winnerId, pl, pr, pk,
      }));
    });

    ws.on("message", (raw: Buffer) => {
      const m = parse(raw.toString());
      if (!m || m.t !== "in") return;
      const d = input.data;
      d.seq = (m.s | 0) >>> 0;
      d.throttle = num(m.th);
      d.steer = num(m.st);
      d.drift = !!m.dr;
      d.boost = !!m.bo;
      d.fire = !!m.f;
      d.aimYaw = num(m.ay);
      d.aimPitch = num(m.ap);
      d.rx = num(m.px);
      d.rz = num(m.pz);
      d.ry = num(m.ry);
      d.rvx = num(m.vx);
      d.rvz = num(m.vz);
      input.send();
    });

    ws.on("close", () => { try { room.leave(); } catch { /* noop */ } });
    ws.on("error", () => { try { room.leave(); } catch { /* noop */ } });
  }
}

const round = (v: number): number => (isFinite(v) ? Math.round(v * 1000) / 1000 : 0);
const num = (v: any): number => (typeof v === "number" && isFinite(v) ? v : 0);
