/**
 * Overdrive Arena — боевой сервер (Sprint 3).
 *
 * Один процесс: Colyseus (WebSocket + matchmake HTTP) + Godot-relay +
 * /health + dev-only /debug + статическая раздача web-demo (два браузера
 * для ручной проверки DoD-2).
 *
 * ENV: PORT=2567, DEBUG=1 — включает /debug-хуки (только для тестов!).
 */
import http from "node:http";
import path from "node:path";
import { fileURLToPath } from "node:url";
import express from "express";
import { Server } from "@colyseus/core";
import { WebSocketTransport } from "@colyseus/ws-transport";
import { BattleRoom } from "./BattleRoom.js";
import { GodotRelay } from "./relay.js";

const PORT = Number(process.env.PORT || 2567);
const DEBUG = process.env.DEBUG === "1";
const HOST = "0.0.0.0";

const httpServer = http.createServer();
const transport = new WebSocketTransport();
transport.attachToServer(httpServer, {
  filter: (req) => !req.url?.startsWith("/godot-relay"),
});

const server = new Server({ transport, gracefullyShutdown: true });
server.define("battle", BattleRoom);

// HTTP-поверхность поверх того же сервера
const app = transport.getExpressApp();
app.get("/health", (_req, res) => {
  res.json({ ok: true, uptime: Math.round(process.uptime()) });
});
const here = path.dirname(fileURLToPath(import.meta.url));
app.use(express.static(path.resolve(here, "../../web-demo")));

if (DEBUG) {
  app.use("/debug/rooms", (_req, res) => {
    const room: any = BattleRoom.last;
    if (!room) return res.json({ rooms: [] });
    res.json(room.debugSnapshot());
  });
  app.post("/debug/teleport", express.json(), (req, res) => {
    const room: any = BattleRoom.last;
    if (!room) return res.status(404).json({ error: "no room" });
    res.json({ ok: room.debugTeleport(String(req.body.sid), Number(req.body.x), Number(req.body.z)) });
  });
  app.post("/debug/hurt", express.json(), (req, res) => {
    const room: any = BattleRoom.last;
    if (!room) return res.status(404).json({ error: "no room" });
    room.debugHurt(String(req.body.sid), Number(req.body.dmg ?? 0), String(req.body.from ?? "debug"));
    res.json({ ok: true });
  });
  app.post("/debug/resetpickups", (_req, res) => {
    const room: any = BattleRoom.last;
    if (!room) return res.status(404).json({ error: "no room" });
    room.debugResetPickups();
    res.json({ ok: true });
  });
  app.post("/debug/heal", express.json(), (req, res) => {
    const room: any = BattleRoom.last;
    if (!room) return res.status(404).json({ error: "no room" });
    room.debugHeal(String(req.body.sid));
    res.json({ ok: true });
  });
  app.post("/debug/pausebot", express.json(), (req, res) => {
    const room: any = BattleRoom.last;
    if (!room) return res.status(404).json({ error: "no room" });
    for (const sid of String(req.body.sid).split(",")) room.debugPauseBot(sid, !!req.body.on);
    res.json({ ok: true });
  });
  app.post("/debug/latency", express.json(), (req, res) => {
    server.simulateLatency(Number(req.body.ms ?? 0));   // round-trip ms
    res.json({ ok: true });
  });
}

await server.listen(PORT, HOST);

const relay = new GodotRelay(httpServer, `ws://127.0.0.1:${PORT}`);
relay.listen();

console.log(
  `[overdrive-server] colyseus on :${PORT} (ws + matchmake HTTP), ` +
  `godot relay ws://0.0.0.0:${PORT}/godot-relay, web-demo http://0.0.0.0:${PORT}/` +
  (DEBUG ? " [DEBUG endpoints ON]" : ""),
);
