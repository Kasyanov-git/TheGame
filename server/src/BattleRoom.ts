/**
 * BattleRoom — авторитарная комната матча (Sprint 3, ТЗ п.1/п.2).
 *
 *  - 4 слота (maxClients=4), patchRate 50 мс (20 Hz снапшотов Colyseus);
 *  - matchmaking-таймер 5.0 с: не хватает людей → слоты заполняются ботами;
 *  - вход реального игрока в «ботовую» комнату выталкивает бота (ТЗ п.3);
 *  - movement: trust-but-validate (клиент шлёт UserCommand c самоотчётом
 *    позиции; сервер верифицирует скорость/рамку арены, иначе — rubber-band);
 *  - урон только серверный (hit validation с лаг-компенсацией Rewind по
 *    renderTime стрелка); HP реплицируется схемой;
 *  - фиксированный шаг симуляции 30 Гц.
 */
import { Room } from "@colyseus/core";
import {
  BattleState, PickupState, PlayerState, ProjectileState, UserCommand,
} from "./schema.js";

type BattleStateI = InstanceType<typeof BattleState>;
type UserCommandI = InstanceType<typeof UserCommand>;
import {
  CAR_REST_Y, PICKUP_RADIUS, PICKUPS, RESPAWN_DELAY, SPAWNS, WEAPONS, wrapAngle, type WeaponType,
} from "./arena.js";
import {
  type InputFrame, type PlayerSim, applyPickup, clampToArena, hitscan,
  newPlayerSim, resetReportBaseline, spawnProjectile, stepPlayer, stepProjectile,
} from "./sim.js";
import { ServerBotController, type BotWorld, type EnemyView } from "./bots.js";

const TICK_RATE = 30;               // Гц симуляции (вход 30–60 Гц, снапшот 20)
const MATCH_TIME = 120.0;           // сек до FINISHED
const FIRE_TOLERANCE = 0.85;        // серверный кулдаун чуть мягче клиента

export class BattleRoom extends Room<{
  state: BattleStateI;
  input: UserCommandI;
}> {

  maxClients = 4;
  patchRate = 50;                    // ТЗ: 20 Hz
  autoDispose = true;

  private sims = new Map<string, PlayerSim>();
  private bots = new Map<string, ServerBotController>();
  private prSims = new Map<string, ReturnType<typeof spawnProjectile>>();
  private prSeq = 0;
  private matchTimer: { clear(): void } | null = null;
  private spawnIdx = 0;
  private botIdx = 0;
  private pausedBots = new Set<string>();  // /debug/pausebot — изоляция сценариев
  private rewind: any = null;
  /** debug-хуки (только NODE_ENV!=production / DEBUG=1) */
  static last: BattleRoom | null = null;

  async onCreate(options: any): Promise<void> {
    this.state = new BattleState();
    this.state.matchState = "WAITING";
    this.state.gameTimer = MATCH_TIME;

    for (let i = 0; i < PICKUPS.length; i++) {
      const pk = PICKUPS[i];
      this.state.pickups.set(String(i), new PickupState({
        type: pk.type, x: pk.x, z: pk.z, cd: 0,
      }));
    }

    this.inputs = this.defineInput(UserCommand, {
      seqField: "seq",
      bufferMaxSize: 64,
      sanitize: {
        throttle: [-1, 1],
        steer: [-1, 1],
        aimYaw: [-8, 8],       // wrapAngle() доведёт до [-π, π]
        aimPitch: [-0.6, 0.6], // запас вокруг клампа ±30°+ 
        rx: [-80, 80], rz: [-60, 60], ry: [-8, 8],
        rvx: [-90, 90], rvz: [-90, 90],
      },
    }) as any;

    // лаг-компенсация: история позиций игроков для отмотки на renderTime
    // стрелка (встроенный Rewind @colyseus/core 0.18)
    this.rewind = this.allowRewindState({ maxRewindMs: 500 });
    this.rewind.attachAll(this.state.players, { fields: ["x", "y", "z"] });

    this.setFixedTimestep(() => this.step(1 / TICK_RATE), TICK_RATE);
    BattleRoom.last = this;
  }

  // ── lifecycle игроков ───────────────────────────────────────────

  onJoin(client: any, options: any): void {
    // комната забита ботами — освобождаем слот человеку (ТЗ п.3)
    while (this.state.players.size >= this.maxClients) this.disconnectBot();
    const weapon: WeaponType = options?.weapon === "mg" ? "mg" : "cannon";
    this.addPlayer(client.sessionId, false, weapon, String(options?.name || client.sessionId.slice(0, 4)));
    // таймер матчмейкинга для «холодного» старта
    if (this.state.matchState === "WAITING" && this.matchTimer === null) {
      // ТЗ: matchmaking_timeout = 5.0 s — затем добивка ботами
      this.matchTimer = this.clock.setTimeout(() => this.fillWithBotsAndStart(), 5000) as any;
    }
    client.send("welcome", { id: client.sessionId, weapon });
    this.broadcastPlayersChanged();
  }

  onLeave(client: any): void {
    const sid = client.sessionId;
    this.state.players.delete(sid);
    this.sims.delete(sid);
    if (this.state.matchState === "WAITING" && this.countHumans() === 0) {
      // последний человек вышел до старта — снимаем таймер (авто-дизпоуз)
      if (this.matchTimer) { this.matchTimer.clear(); this.matchTimer = null; }
      for (const b of [...this.bots.keys()]) this.removeBot(b);
    }
    this.broadcastPlayersChanged();
  }

  onDispose(): void {
    if (BattleRoom.last === this) BattleRoom.last = null;
  }

  // ── состав ───────────────────────────────────────────────────────

  private addPlayer(sid: string, bot: boolean, weapon: WeaponType, name: string): void {
    const [sx, sz] = SPAWNS[this.spawnIdx++ % SPAWNS.length];
    const p = new PlayerState({
      id: sid, name, x: sx, y: CAR_REST_Y, z: sz,
      rotY: Math.atan2(sx, sz),   // курсом к центру арены
      hp: 100, weaponType: weapon, isBot: bot,
    });
    this.state.players.set(sid, p);
    const sim = newPlayerSim(sid, bot, weapon, name);
    this.sims.set(sid, sim);
    resetReportBaseline(sim, p.x, p.z);   // baseline = точка спавна (иначе первый же репорт — «телепорт»)
    if (bot) this.bots.set(sid, new ServerBotController());
  }

  private fillWithBotsAndStart(): void {
    this.matchTimer = null;
    while (this.state.players.size < this.maxClients) {
      this.botIdx++;
      this.addPlayer(`bot-${this.rand()}`, true, "cannon", `Bot ${this.botIdx}`);
    }
    this.state.matchState = "PLAYING";
    this.state.gameTimer = MATCH_TIME;
    this.broadcast("ev", { e: "start" });
  }

  private disconnectBot(): string | null {
    // самый «слабый» бот (по киллам), иначе первый
    let weakest: string | null = null;
    let best = Infinity;
    for (const [sid, p] of this.state.players) {
      if (!p.isBot) continue;
      if (p.score < best) { best = p.score; weakest = sid; }
    }
    if (weakest) this.removeBot(weakest);
    return weakest;
  }

  private removeBot(sid: string): void {
    this.state.players.delete(sid);
    this.sims.delete(sid);
    this.bots.delete(sid);
    this.broadcast("ev", { e: "leave", a: { id: sid } });
  }

  private countHumans(): number {
    let n = 0;
    for (const [, p] of this.state.players) if (!p.isBot) n++;
    return n;
  }

  // ── шаг симуляции ────────────────────────────────────────────────

  private step(dt: number): void {
    if (this.state.matchState === "PLAYING") {
      this.state.gameTimer = Math.max(0, this.state.gameTimer - dt);
      if (this.state.gameTimer <= 0) this.endMatch();
    }

    // 1) ввод + движение
    for (const [sid, p] of this.state.players) {
      const sim = this.sims.get(sid);
      if (!sim) continue;

      if (p.hp <= 0) {   // мёртв — только отсчёт респавна
        sim.respawnT -= dt;
        if (sim.respawnT <= 0) this.respawn(sid, p, sim);
        continue;
      }

      let frame: InputFrame | null = null;
      let haveReport = false;
      if (sim.bot) {
        const bot = this.pausedBots.has(sid) ? null : this.bots.get(sid);
        if (bot) {
          frame = bot.update(
            { x: p.x, z: p.z, hp: p.hp, boostT: sim.boostT, yaw: p.rotY, aimYaw: sim.aimYaw },
            this.botWorld(sid), dt,
          );
        }
      } else {
        const frames = this.drainInputs(sid);
        if (frames) {
          frame = frames.frame;
          haveReport = frames.hadFrame;
        }
      }
      if (!frame) {
        // idle-ввод: катимся накатом (drag уже в stepPlayer)
        frame = { throttle: 0, steer: 0, drift: false, boost: false, fire: false, aimYaw: sim.aimYaw, aimPitch: 0 };
      }

      const reportOk = stepPlayer(p as any, sim, frame, dt, haveReport);
      if (!reportOk && haveReport && !sim.bot && sim.trust < 0.6) {
        // отчёт отвергнут и доверие низкое — честный rubber-band клиенту
        this.clients.get(sid)?.send("reconcile", { x: p.x, z: p.z, rotY: p.rotY });
      }

      // таймеры эффектов
      sim.shieldT = Math.max(0, sim.shieldT - dt);
      sim.boostT = Math.max(0, sim.boostT - dt);
      sim.fireCd = Math.max(0, sim.fireCd - dt);
      p.shieldT = sim.shieldT;
      p.boostT = sim.boostT;
      p.aimYaw = sim.aimYaw;
      p.aimPitch = sim.aimPitch;
      p.vx = sim.vfx;
      p.vz = sim.vfz;

      // 2) огонь (только PLAYING)
      if (frame.fire && this.state.matchState === "PLAYING" && sim.fireCd <= 0) {
        this.fireWeapon(sid, p, sim, frame);
      }
    }

    // 3) снаряды
    this.stepProjectiles(dt);
    // 4) пикапы
    this.stepPickups(dt);
  }

  private drainInputs(sid: string): { frame: InputFrame; hadFrame: boolean } | null {
    const acc = this.inputs?.get(sid);
    if (!acc) return null;
    let latest: any = null;
    let fire = false;
    try {
      for (const inp of acc) {   // consume — по одному, с дедупом по seq
        latest = inp;
        fire = fire || !!inp.fire;
      }
    } catch {
      latest = acc.latest;
    }
    if (!latest) return null;
    return {
      frame: {
        throttle: latest.throttle, steer: latest.steer, drift: !!latest.drift,
        boost: !!latest.boost, fire,
        aimYaw: wrapAngle(latest.aimYaw), aimPitch: latest.aimPitch,
        rx: latest.rx, ry: latest.ry, rz: latest.rz, rvx: latest.rvx, rvz: latest.rvz,
      } as any,
      hadFrame: true,
    };
  }

  // ── стрельба и урон ──────────────────────────────────────────────

  private fireWeapon(sid: string, p: any, sim: PlayerSim, frame: InputFrame): void {
    const w = WEAPONS[sim.weapon];
    sim.fireCd = w.fireRate * FIRE_TOLERANCE;
    const yaw = sim.aimYaw, pitch = sim.aimPitch;

    if (w.hitscan) {
      // отмотка целей на renderTime стрелка (лаж-компенсация сервера)
      const seen = this.rewind?.lastSeenBy(sid);
      const targets: Array<{ id: string; x: number; y: number; z: number; hp: number }> = [];
      for (const [tid, t] of this.state.players) {
        if (tid === sid || t.hp <= 0) continue;
        let x = t.x, y = t.y, z = t.z;
        if (seen) { const r = seen.read(t, ["x", "y", "z"]); x = r.x; y = r.y; z = r.z; }
        targets.push({ id: tid, x, y, z, hp: t.hp });
      }
      const res = hitscan([p.x, p.y + 0.75, p.z], yaw, pitch, w.range, targets);
      this.broadcast("ev", { e: "fire", a: { id: sid, x: p.x, y: p.y, z: p.z, yaw, pitch, w: sim.weapon } });
      if (res.hitId) this.applyDamage(res.hitId, sid, w.damage, res.end);
      return;
    }

    const pr = spawnProjectile(`${sid.slice(0, 4)}-${this.prSeq++}`, sid, [p.x, p.y, p.z], yaw, pitch, sim.weapon);
    this.prSims.set(pr.id, pr);
    this.state.projectiles.set(pr.id, new ProjectileState({
      ownerId: sid, x: pr.x, y: pr.y, z: pr.z,
      vx: pr.vx, vy: pr.vy, vz: pr.vz, damage: pr.damage, hitscan: false,
    }));
    this.broadcast("ev", { e: "fire", a: { id: sid, x: p.x, y: p.y, z: p.z, yaw, pitch, w: sim.weapon } });
  }

  private stepProjectiles(dt: number): void {
    if (this.prSims.size === 0) return;
    const targets = [...this.state.players.entries()].map(([id, t]) => ({
      id, x: t.x, y: t.y, z: t.z, hp: t.hp,
    }));
    for (const [id, pr] of [...this.prSims]) {
      const res = stepProjectile(pr, dt, targets);
      const ent = this.state.projectiles.get(id);
      if (ent) { ent.x = pr.x; ent.y = pr.y; ent.z = pr.z; }
      if (res.hitId) {
        this.applyDamage(res.hitId, pr.ownerId, pr.damage, res.point!);
        this.prSims.delete(id);
        this.state.projectiles.delete(id);
      } else if (res.expired) {
        this.prSims.delete(id);
        this.state.projectiles.delete(id);
      }
    }
  }

  /** Единственная точка начисления урона — сервер. */
  private applyDamage(tgtSid: string, attackerSid: string, amount: number, at: [number, number, number]): void {
    const t = this.state.players.get(tgtSid);
    const sim = this.sims.get(tgtSid);
    if (!t || !sim || t.hp <= 0) return;
    if (sim.shieldT > 0) {          // щит поглощает полностью (S2-семантика)
      this.broadcast("ev", { e: "shield-absorb", a: { id: tgtSid, x: t.x, y: t.y, z: t.z } });
      return;
    }
    t.hp = Math.max(0, t.hp - amount);
    const killed = t.hp <= 0;
    this.broadcast("ev", {
      e: "hit", a: { id: tgtSid, from: attackerSid, dmg: amount, x: at[0], y: at[1], z: at[2], kill: killed },
    });
    const bot = this.bots.get(tgtSid);
    if (bot) bot.onDamaged(attackerSid);
    if (killed) {
      sim.respawnT = RESPAWN_DELAY;
      const a = this.state.players.get(attackerSid);
      if (a) a.score += 1;
      this.broadcast("ev", { e: "kill", a: { by: attackerSid, victim: tgtSid } });
      this.broadcast("ev", { e: "death", a: { id: tgtSid, x: t.x, y: t.y, z: t.z } });
    }
  }

  private respawn(sid: string, p: any, sim: PlayerSim): void {
    const [sx, sz] = SPAWNS[this.spawnIdx++ % SPAWNS.length];
    p.x = sx; p.y = CAR_REST_Y; p.z = sz;
    p.rotY = Math.atan2(p.x, p.z);
    p.vx = 0; p.vz = 0;
    p.hp = 100;
    sim.respawnT = 0;
    sim.shieldT = 0; sim.boostT = 0;
    resetReportBaseline(sim, p.x, p.z);   // иначе первые репорты после респауна — «телепорт»
    this.broadcast("ev", { e: "spawn", a: { id: sid, x: p.x, y: p.y, z: p.z } });
  }

  // ── пикапы ───────────────────────────────────────────────────────

  private stepPickups(dt: number): void {
    for (const [id, pk] of this.state.pickups) {
      if (pk.cd > 0) { pk.cd = Math.max(0, pk.cd - dt); continue; }
      for (const [sid, p] of this.state.players) {
        if (p.hp <= 0) continue;
        if (Math.abs(p.x - pk.x) + Math.abs(p.z - pk.z) > PICKUP_RADIUS * 2) continue;
        if (Math.hypot(p.x - pk.x, p.z - pk.z) <= 2.8) {
          const sim = this.sims.get(sid)!;
          pk.cd = applyPickup(sim, pk.type, p as any);
          this.broadcast("ev", { e: "pickup", a: { id: sid, type: pk.type, x: pk.x, z: pk.z } });
          break;
        }
      }
    }
  }

  // ── служебное ────────────────────────────────────────────────────

  private botWorld(exceptSid: string): BotWorld {
    const enemies: EnemyView[] = [];
    for (const [sid, p] of this.state.players) {
      if (sid === exceptSid || p.hp <= 0) continue;
      enemies.push({ sid, x: p.x, z: p.z, vx: p.vx, vz: p.vz, hp: p.hp });
    }
    const pickups = [...this.state.pickups.entries()].map(([id, pk]) => ({
      id: Number(id), type: pk.type, x: pk.x, z: pk.z, cd: pk.cd,
    }));
    return { enemies, pickups };
  }

  private broadcastPlayersChanged(): void {
    this.broadcast("ev", { e: "roster", a: { n: this.state.players.size } });
  }

  private endMatch(): void {
    if (this.state.matchState !== "PLAYING") return;
    this.state.matchState = "FINISHED";
    let best: string | null = null;
    let bs = -1;
    for (const [sid, p] of this.state.players) {
      if (p.score > bs) { bs = p.score; best = sid; }
    }
    this.state.winnerId = best ?? "";
    this.broadcast("ev", { e: "finished", a: { winner: best } });
  }

  /** Отладка/тесты: мгновенная позиция (обходит анти-чит на этот тик). */
  debugTeleport(sid: string, x: number, z: number): boolean {
    const p = this.state.players.get(sid);
    if (!p) return false;
    p.x = x; p.z = z; p.y = CAR_REST_Y;
    clampToArena(p as any);
    const sim = this.sims.get(sid);
    if (sim) resetReportBaseline(sim, p.x, p.z);  // чтобы «клиент» не отлетел rubber-band'ом
    return true;
  }

  debugPauseBot(sid: string, on: boolean): void {
    if (on) this.pausedBots.add(sid);
    else this.pausedBots.delete(sid);
  }

  debugResetPickups(): void {
    for (const [, pk] of this.state.pickups) pk.cd = 0;
  }

  debugHeal(sid: string): void {
    const p = this.state.players.get(sid);
    if (p && p.hp > 0) {
      p.hp = 100;
      const sim = this.sims.get(sid);
      if (sim) { sim.shieldT = 0; sim.respawnT = 0; }   // hurt-тесты не должен глушить щит
      p.shieldT = 0;
    }
  }

  debugHurt(sid: string, amount: number, from: string = "debug"): void {
    this.applyDamage(sid, from, amount, [0, 0, 0]);
  }

  debugBotState(sid: string): { mode: string; target: string | null; seek: number | null } | null {
    return this.bots.get(sid)?.debugState ?? null;
  }

  debugTrust(sid: string): number {
    return this.sims.get(sid)?.trust ?? -1;
  }

  /** /debug/rooms — снимок для автотестов (только DEBUG=1). */
  debugSnapshot(): any {
    const players: any[] = [];
    for (const [sid, p] of this.state.players) {
      players.push({
        sid, hp: p.hp, x: Math.round(p.x * 100) / 100, z: Math.round(p.z * 100) / 100,
        score: p.score, bot: p.isBot, trust: Math.round((this.sims.get(sid)?.trust ?? -1) * 100) / 100,
        name: p.name,
      });
    }
    const bots: Record<string, any> = {};
    for (const [sid, b] of this.bots) bots[sid] = b.debugState;
    return {
      matchState: this.state.matchState, gameTimer: this.state.gameTimer,
      players, bots, projectiles: this.state.projectiles.size,
      pickups: [...this.state.pickups].map(([, k]: any) => ({ type: k.type, cd: Math.round(k.cd * 10) / 10 })),
    };
  }

  private rand(): number {
    return Math.floor(Math.random() * 1e9);
  }
}
