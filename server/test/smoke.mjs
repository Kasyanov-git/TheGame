/**
 * E2E-смоук боевого сервера (Sprint 3). Без фреймворков: spawn сервера +
 * @colyseus/sdk клиенты + godot-relay ws. Покрывает DoD 1–4 + анти-чит +
 * rate limit + FSM ботов + лаг-компенсацию.  npm test (нужен build).
 */
import { spawn } from "node:child_process";
import { setTimeout as sleep } from "node:timers/promises";
import { ColyseusSDK } from "@colyseus/sdk";
import { WebSocket } from "ws";

const PORT = Number(process.env.TEST_PORT || 2567);
const URL = `ws://127.0.0.1:${PORT}`;

let passes = 0;
const fails = [];
function check(cond, msg) {
  if (cond) { passes++; console.log(`  OK   ${msg}`); }
  else { fails.push(msg); console.log(`  FAIL ${msg}`); }
}

async function waitFor(fn, ms, label) {
  const t0 = Date.now();
  while (Date.now() - t0 < ms) {
    let ok = false;
    try { ok = await fn(); } catch { /* polling */ }
    if (ok) return true;
    await sleep(80);
  }
  throw new Error(`timeout waiting for: ${label}`);
}

// ── сервер ─────────────────────────────────────────────────────────
const srv = spawn(process.execPath, ["dist/index.js"], {
  env: { ...process.env, PORT: String(PORT), DEBUG: "1", NODE_ENV: "test" },
  stdio: ["ignore", "pipe", "pipe"],
});
let srvOut = "";
srv.stdout.on("data", (d) => { srvOut += d; });
srv.stderr.on("data", (d) => { srvOut += d; });

async function debug(path, body, method) {
  const res = await fetch(`http://127.0.0.1:${PORT}${path}`, {
    method: method || (body ? "POST" : "GET"),
    headers: { "content-type": "application/json" },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!res.ok) throw new Error(`${path} → HTTP ${res.status}`);
  return res.json();
}

function watch(room, bag) {
  bag.players = new Map();
  bag.events = [];
  room.onStateChange((s) => {
    bag.match = s.matchState;
    bag.timer = s.gameTimer;
    bag.players = new Map();
    s.players.forEach((p, id) => bag.players.set(id, p));
    bag.prCount = s.projectiles.size;
  });
  room.onMessage("ev", (d) => bag.events.push(d));
}

const joinBattle = async (name, weapon) => {
  const client = new ColyseusSDK(URL);
  return client.joinOrCreate("battle", { name, weapon });
};

let A, B, bagA, bagB, ihA, seq = 0;
const sendA = (over = {}) => {
  Object.assign(ihA.data, { seq: ++seq, throttle: 0, steer: 0, fire: false, ...over });
  ihA.send();
};

try {
  await waitFor(async () => (await fetch(`http://127.0.0.1:${PORT}/health`)).ok, 15000, "server health");
  console.log("== server up (DoD 1: ws-транспорт отвечает) ==");

  // ══ DoD 3: одиночный вход → +5 s → три бота ═══════════════════
  A = await joinBattle("A", "cannon");
  bagA = {}; watch(A, bagA);
  await waitFor(() => bagA.players.size === 1, 4000, "state sync");
  check(bagA.players.get(A.sessionId).hp === 100, "join: player created with full hp");

  await waitFor(() => bagA.players.size === 4, 8000, "bots fill");
  const bots0 = [...bagA.players.values()].filter((p) => p.isBot);
  check(bots0.length === 3, `matchmaking_timeout 5s: 3 bots spawned (got ${bots0.length})`);

  // боты «ведут бой»: двигаются
  const botMoveId = bots0[0].id;
  const p0 = { x: bots0[0].x, z: bots0[0].z };
  await sleep(1600);
  const bc = bagA.players.get(botMoveId);
  const moved = Math.hypot(bc.x - p0.x, bc.z - p0.z);
  check(moved > 1.0, `bots drive the arena (moved ${moved.toFixed(1)} m in 1.6 s)`);

  // ══ динамическая замена: человек вытесняет бота ═══════════════
  B = await joinBattle("B", "mg");
  bagB = {}; watch(B, bagB);
  await waitFor(() => bagB.players.size === 4 && [...bagB.players.values()].filter((p) => p.isBot).length === 2, 5000, "bot replaced");
  const nBots = [...bagB.players.values()].filter((p) => p.isBot).length;
  check(nBots === 2, `disconnectBot() on human join (bots left: ${nBots})`);

  // ══ DoD 2: предсказание + репликация без телепортов ═══════════
  ihA = A.input();
  await sleep(200);
  const aBefore = { ...bagB.players.get(A.sessionId) };
  // «клиентская физика» в тесте: та же модель, что у Godot/Three-клиента
  let cpx = aBefore.x, cpz = aBefore.z, cv = 0, cyaw = aBefore.rotY;
  const t0 = Date.now();
  let maxJump = 0;
  let prevPos = null;
  while (Date.now() - t0 < 1500) {              // 30 Гц UserCommand
    const dt = 0.033;
    cv = Math.min(45, cv + 13.3 * dt);
    cyaw += (cv / 2.7) * Math.tan(-0.25 * 0.61) * dt;
    cpx += -Math.sin(cyaw) * cv * dt;
    cpz += -Math.cos(cyaw) * cv * dt;
    sendA({
      throttle: 1, steer: -0.25,
      rx: cpx, rz: cpz, ry: cyaw,
      rvx: -Math.sin(cyaw) * cv, rvz: -Math.cos(cyaw) * cv,
    });
    const p = bagB.players.get(A.sessionId);
    if (p && prevPos) maxJump = Math.max(maxJump, Math.hypot(p.x - prevPos.x, p.z - prevPos.z));
    if (p) prevPos = { x: p.x, z: p.z };
    await sleep(33);
  }
  const aAfter = bagB.players.get(A.sessionId);
  const drove = Math.hypot(aAfter.x - aBefore.x, aAfter.z - aBefore.z);
  check(drove > 8, `remote movement synced (${drove.toFixed(1)} m driven, seen by B)`);
  check(maxJump < 6.5, `no teleport in 20 Hz snapshots (max step ${maxJump.toFixed(2)} m)`);
  const drift = Math.hypot(aAfter.x - ihA.data.rx, aAfter.z - ihA.data.rz);
  check(drift < 2.5, `server follows client prediction closely (drift ${drift.toFixed(2)} m)`);

  // ══ анти-чит: телепорт-репорт отвергнут ═══════════════════════
  for (let i = 0; i < 12; i++) { sendA({ rx: 500, rz: 0 }); await sleep(40); }
  await sleep(300);
  let dbg = await debug("/debug/rooms");
  const aRow = dbg.players.find((r) => r.sid === A.sessionId);
  check(Math.abs(aRow.x) < 60 && Math.abs(aRow.z) < 60, "cheated report rejected (server kept sane pos)");
  check(aRow.trust < 1, `trust degraded on rejected reports (${aRow.trust})`);

  // ══ rate limit сервера (fire_rate авторитарный) ══════════════
  // все боты на паузе — иначе они убивают A раньше времени и сценарии
  // теряют детерминизм (FFA есть FFA)
  {
    const d0 = await debug("/debug/rooms");
    await debug("/debug/pausebot", { sid: d0.players.filter((x) => x.bot).map((x) => x.sid).join(","), on: true });
  }
  await debug("/debug/teleport", { sid: A.sessionId, x: 0, z: 12 });
  await debug("/debug/teleport", { sid: B.sessionId, x: 0, z: 24 });
  await sleep(150);
  bagB.events.length = 0;
  const tR = Date.now();
  while (Date.now() - tR < 1000) {
    sendA({ throttle: 0, fire: true, rx: 0, rz: 12, ry: -Math.PI / 2, aimYaw: -Math.PI / 2, aimPitch: 0.5, rvx: 0, rvz: 0 });
    await sleep(28);
  }
  const shots = bagB.events.filter((e) => e.e === "fire" && e.a.id === A.sessionId).length;
  check(shots >= 4 && shots <= 9, `server fire cap for 0.15s (got ${shots}/s, spam 30+/s ignored)`);

  // ══ DoD 4: снарядный урон через сервер ═══════════════════════
  await debug("/debug/heal", { sid: B.sessionId });
  bagB.events.length = 0;
  await sleep(250);
  bagB.events.length = 0;
  let hpSeen = 100;
  const tH = Date.now();
  while (Date.now() - tH < 5000) {
    sendA({ throttle: 0, fire: true, rx: 0, rz: 12, ry: Math.PI, aimYaw: Math.PI, aimPitch: 0, rvx: 0, rvz: 0 });
    await sleep(45);
    const pB = bagA.players.get(B.sessionId);
    if (pB && pB.hp < 100) { hpSeen = pB.hp; break; }
  }
  check(hpSeen <= 85 && (100 - hpSeen) % 15 === 0, `projectile damage quantized by 15 (100 → ${hpSeen})`);
  await sleep(700);   // патч с событиями дошёл до B
  check(bagB.events.some((e) => e.e === "fire" && e.a.id === A.sessionId), "fire event replicated to victim");
  check(bagB.events.some((e) => e.e === "hit" && e.a.id === B.sessionId), "hit_registered event on victim client");

  // ══ убийство → респавн за 4 с → score ════════════════════════
  // детерминизм: боты убраны «далеко», B ослаблен сервером, A предварительно
  // сводит турель — добивание гарантирует, что kill принадлежит A.
  dbg = await debug("/debug/rooms");
  for (const r of dbg.players.filter((r) => r.bot)) {
    await debug("/debug/teleport", { sid: r.sid, x: 0, z: -30 });
  }
  await debug("/debug/teleport", { sid: A.sessionId, x: 0, z: 18 });
  await debug("/debug/teleport", { sid: B.sessionId, x: 0, z: 24 });
  await debug("/debug/hurt", { sid: B.sessionId, dmg: 85, from: A.sessionId });
  const tPre = Date.now();
  while (Date.now() - tPre < 500) {   // сход турели (12 рад/с) без огня
    sendA({ throttle: 0, rx: 0, rz: 18, ry: Math.PI, aimYaw: Math.PI, aimPitch: 0, rvx: 0, rvz: 0 });
    await sleep(33);
  }
  const tK = Date.now();
  while (Date.now() - tK < 7000) {
    sendA({ throttle: 0, fire: true, rx: 0, rz: 18, ry: Math.PI, aimYaw: Math.PI, aimPitch: 0, rvx: 0, rvz: 0 });
    await sleep(40);
    const pB = bagA.players.get(B.sessionId);
    if (pB && pB.hp === 0) break;
  }
  const killEv = bagB.events.find((e) => e.e === "kill" && e.a.victim === B.sessionId && e.a.by === A.sessionId);
  check(!!killEv, "kill: server broadcast kill event attributed to shooter");
  await waitFor(() => bagA.players.get(A.sessionId)?.score >= 1, 3000, "score replicate").then(
    () => check(true, "kill credited to shooter score"),
    () => check(false, "kill credited to shooter score"),
  );
  const deadPos = { x: bagA.players.get(B.sessionId).x, z: bagA.players.get(B.sessionId).z };
  await waitFor(() => bagA.players.get(B.sessionId)?.hp === 100, 7000, "respawn");
  const rp = bagA.players.get(B.sessionId);
  check(Math.hypot(rp.x - deadPos.x, rp.z - deadPos.z) > 2, "respawn at spawn point after 4 s");

  // ══ FSM ботов: урон → SEEK_PICKUP → ремонт ═══════════════════
  dbg = await debug("/debug/rooms");
  const botRow = dbg.players.find((r) => r.bot);
  await debug("/debug/pausebot", { sid: botRow.sid, on: false });  // подопытный активен
  const otherBots = dbg.players.filter((r) => r.bot && r.sid !== botRow.sid).map((r) => r.sid).join(",");
  if (otherBots) await debug("/debug/pausebot", { sid: otherBots, on: true });
  await debug("/debug/heal", { sid: botRow.sid });
  await debug("/debug/resetpickups", null, "POST");
  await sleep(120);
  await debug("/debug/hurt", { sid: botRow.sid, dmg: 85, from: A.sessionId });
  await sleep(150);
  dbg = await debug("/debug/rooms");
  const bst = dbg.bots[botRow.sid];
  check(bst?.mode === "SEEK_PICKUP", `bot FSM → SEEK_PICKUP below 40% hp (mode=${bst?.mode})`);
  check(bst?.lastHitBy === A.sessionId, `bot remembers who damaged it (lastHitBy=${bst?.lastHitBy === A.sessionId ? "shooter" : bst?.lastHitBy})`);
  await debug("/debug/teleport", { sid: botRow.sid, x: 27.4, z: 0 });   // у RepairEast
  await debug("/debug/resetpickups", null, "POST");
  await debug("/debug/teleport", { sid: botRow.sid, x: 27.4, z: 0 });
  let botHealed = false;
  const tP = Date.now();
  while (Date.now() - tP < 6000 && !botHealed) {
    const d = await debug("/debug/rooms");
    botHealed = (d.players.find((r) => r.sid === botRow.sid)?.hp ?? 0) > 45;
    if (!botHealed) await sleep(200);
  }
  check(botHealed, "server applied repair pickup to bot (+35) via SEEK_PICKUP walk");
  await debug("/debug/pausebot", { sid: botRow.sid, on: true });   // сценарий закончил — тишина

  // ══ RTT 300 мс: стабильность синхронизации и хит-детекта ════
  // изоляция сценария: A жив/полон, все боты на паузе
  await debug("/debug/heal", { sid: A.sessionId });
  {
    const d0 = await debug("/debug/rooms");
    await debug("/debug/pausebot", { sid: d0.players.filter((x) => x.bot).map((x) => x.sid).join(","), on: true });
  }
  await debug("/debug/latency", { ms: 300 });
  await debug("/debug/teleport", { sid: B.sessionId, x: -14, z: 0 });
  await debug("/debug/teleport", { sid: A.sessionId, x: -14, z: 10 });
  await sleep(400);
  const ihB = B.input();
  let seqB = 0;
  const hpABefore = bagB.players.get(A.sessionId).hp;
  const tL = Date.now();
  let az = bagB.players.get(A.sessionId).z;
  let lagHit = false;
  while (Date.now() - tL < 5000 && !lagHit) {
    Object.assign(ihB.data, {
      seq: ++seqB, throttle: 0, steer: 0, fire: true,
      aimYaw: Math.PI, aimPitch: 0, rx: -14, rz: 0, ry: Math.PI, rvx: 0, rvz: 0,
    });
    ihB.send();
    az += 45 * 0.033;                                  // A уходит по лучу (отрыв)
    sendA({ throttle: 1, steer: 0, rx: -14, rz: az, ry: Math.PI, rvx: 0, rvz: 45, fire: false });
    await sleep(33);
    const pa = bagB.players.get(A.sessionId);
    if (pa && pa.hp < hpABefore) lagHit = true;
  }
  if (!lagHit) {
    const d = await debug("/debug/rooms");
    const row = d.players.find((r) => r.sid === A.sessionId);
    console.log(`  [dbg] A server pos: (${row?.x}, ${row?.z}) trust=${row?.trust} hp=${row?.hp}`);
    console.log(`  [dbg] events: fire=${bagB.events.filter(e => e.e === "fire" && e.a.id === B.sessionId).length} hit=${bagB.events.filter(e => e.e === "hit").length}`);
  }
  check(lagHit, `MG hitscan hits fleeing target under 300 ms RTT (dmg ${100 - bagB.players.get(A.sessionId).hp})`);
  // самоотчёт по-прежнему принимается при лаге (нет rubber-band шторма)
  const aTrust = (await debug("/debug/rooms")).players.find((r) => r.sid === A.sessionId).trust;
  check(aTrust >= 0.9, `reports accepted under latency (trust ${aTrust})`);
  await debug("/debug/latency", { ms: 0 });
  await sleep(250);

  // ══ Godot relay: ws + snapshot + events (транспорт движка) ════
  const ws = new WebSocket(`ws://127.0.0.1:${PORT}/godot-relay`);
  await new Promise((res, rej) => { ws.on("open", res); ws.on("error", rej); });
  let relaySnap = null;
  let relayId = null;
  const relayEvents = [];
  ws.on("message", (raw) => {
    const m = JSON.parse(raw.toString());
    if (m.t === "ok") relayId = m.id;
    else if (m.t === "st") relaySnap = m;
    else if (m.t === "ev") relayEvents.push(m);
  });
  await waitFor(() => relayId !== null && relaySnap !== null, 6000, "relay welcome+snapshot");
  check(relaySnap.pl.length >= 4, `godot relay: full snapshot (${relaySnap.pl.length} players incl. bots)`);
  const me0 = relaySnap.pl.find((r) => r[0] === relayId);
  const tW = Date.now();
  let s2 = 0;
  while (Date.now() - tW < 1200) {
    s2++;
    ws.send(JSON.stringify({ t: "in", s: s2, th: 1, st: 0, f: 1, ay: 0, ap: 0, vx: 0, vz: -12 }));
    await sleep(40);
  }
  const me1 = relaySnap.pl.find((r) => r[0] === relayId);
  const relayMoved = Math.hypot(me1[1] - me0[1], me1[2] - me0[2]);
  check(relayMoved > 4, `godot relay player driven (${relayMoved.toFixed(1)} m)`);
  check(relayEvents.some((e) => e.e === "fire"), "godot relay receives fire events");
  ws.close();

  console.log(`\nSMOKE3: ${passes} passes, ${fails.length} fails`);
  if (fails.length) { for (const f of fails) console.log("  FAILED: " + f); process.exitCode = 1; }
} catch (e) {
  console.error("SMOKE3 ABORTED:", e.message);
  console.log("--- server log tail ---\n" + srvOut.slice(-3000));
  process.exitCode = 1;
} finally {
  try { A?.leave(); B?.leave(); } catch { /* noop */ }
  srv.kill("SIGTERM");
  await sleep(250);
  srv.kill("SIGKILL");
}
