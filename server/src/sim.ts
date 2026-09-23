/**
 * Серверная симуляция (Sprint 3): движение, валидация самоотчёта клиента,
 * снаряды и хит-тесты. Детерминированно, без wall-clock внутри шага —
 * только фиксированный dt (урок смоука Sprint 1/2).
 */
import {
  ACCEL, BRAKE_DECEL, CAR_REST_Y, DRAG, FLOOR_A, FLOOR_B, HITBOX_R,
  MAX_SPEED, NITRO_TIME, PITCH_MAX, PITCH_MIN, PICKUP_COOLDOWN,
  PICKUP_RADIUS, PROJECTILE_TRIGGER_R, REPAIR_HEAL, REVERSE_MAX, SHIELD_TIME,
  STEER_KEEP_HIGH, STEER_LIMIT, TURRET_SPEED, WHEELBASE, WEAPONS, wrapAngle,
  type WeaponType,
} from "./arena.js";

/** Сюжетная скорость, при которой «отчёт» клиента всё ещё физически возможен
 *  (лимит 45×1.5 нитро + допуск на джиттер пакетов). */
const SPEED_CAP = MAX_SPEED * 1.5 + 6.0;
/** Допуск «телепорта» поверх скорости (м) — больше = резайт с rubber-band. */
const TELEPORT_MARGIN = 3.0;

export interface PlayerSim {
  sid: string;
  bot: boolean;
  weapon: WeaponType;
  /** турель (мировой yaw/pitch ствола) — ограничена TURRET_SPEED, как в Godot */
  aimYaw: number;
  aimPitch: number;
  /** состояние «мертв до» (сек) */
  respawnT: number;
  fireCd: number;
  /** регенерация/расход буста нет — только таймер нитро и щита */
  shieldT: number;
  boostT: number;
  /** скорость для dead-reckoning (когда пакетов нет / отчёт отвергнут) */
  vfx: number;
  vfz: number;
  /** последнее валидное время самоотчёта (ms) — анти-флуд телепортами */
  lastSeq: number;
  trust: number;            // 0..1 — доля принятых отчётов (для отладки/ботов нет)
  name: string;
  /** baseline последнего ПРИНЯТОГО самоотчёта: скорость валидируется между
   *  репортами клиента (а не против серверного DR — иначе серверный телепорт
   *  игрока «ломает» ему синхронизацию: респаун/админ-телепорт/вход) */
  repX: number;
  repZ: number;
  repAtMs: number;
}

export interface InputFrame {
  throttle: number; steer: number; drift: boolean; boost: boolean; fire: boolean;
  aimYaw: number; aimPitch: number;
  rx?: number; ry?: number; rz?: number;
  rvx?: number; rvz?: number;
}

/** Вектор «лица» (Godot convention: forward = basis -Z). */
export function fwdOf(yaw: number): [number, number] {
  return [-Math.sin(yaw), -Math.cos(yaw)];
}

export function newPlayerSim(sid: string, bot: boolean, weapon: WeaponType, name: string): PlayerSim {
  return {
    sid, bot, weapon, aimYaw: 0, aimPitch: 0, respawnT: 0, fireCd: 0,
    shieldT: 0, boostT: 0, vfx: 0, vfz: 0, lastSeq: -1, trust: 1, name,
    repX: NaN, repZ: NaN, repAtMs: 0,
  };
}

/** Сброс baseline репортов (join/телепорт от сервера/респавн). */
export function resetReportBaseline(sim: PlayerSim, x: number, z: number): void {
  sim.repX = x;
  sim.repZ = z;
  sim.repAtMs = performance.now();
}

/**
 * Движение. Для людей: если есть свежий валидный самоотчёт — берём его
 * (клиент — источник своей физики, классика казуального web-неткода),
 * сервер при этом держит dead-reckoning копия для пауз. Для ботов — только
 * интеграция. Возвращает false, если отчёт отвергнут (нужен rubber-band).
 */
export function stepPlayer(
  p: { x: number; y: number; z: number; rotY: number; vx: number; vy: number; vz: number },
  sim: PlayerSim,
  inp: InputFrame,
  dt: number,
  haveReport: boolean,
): boolean {
  // 1) собственная интеграция (dead-reckoning / база для ботов)
  const nitro = sim.boostT > 0 ? 1.5 : 1.0;
  const vCap = MAX_SPEED * nitro;
  let v = Math.hypot(p.vx, p.vz);
  const [fx, fz] = fwdOf(p.rotY);
  // продольное ускорение/торможение
  if (inp.throttle > 0.02) v += ACCEL * inp.throttle * nitro * dt;
  else if (inp.throttle < -0.02) v += BRAKE_DECEL * inp.throttle * dt;
  else v -= Math.sign(v) * Math.min(Math.abs(v), DRAG * v * dt + 2.0 * dt);
  v = Math.max(-REVERSE_MAX, Math.min(vCap, v));
  // руление — велосипедная модель, лимит сужается на скорости
  const speedFrac = Math.min(1, Math.abs(v) / MAX_SPEED);
  const steerLim = STEER_LIMIT * (1 - (1 - STEER_KEEP_HIGH) * speedFrac);
  const delta = inp.steer * steerLim;
  const yawRate = (v / WHEELBASE) * Math.tan(delta);
  // применяем к серверной копии
  p.rotY = wrapAngle(p.rotY + yawRate * dt);
  p.vx = fx * v;
  p.vz = fz * v;
  p.x += p.vx * dt;
  p.z += p.vz * dt;
  p.y = CAR_REST_Y;

  // 2) доводка турели (тоже ограничение 12 рад/с — «вес орудия» честный)
  const maxStep = TURRET_SPEED * dt;
  sim.aimYaw = wrapAngle(
    sim.aimYaw + clamp(wrapAngle(inp.aimYaw - sim.aimYaw), -maxStep, maxStep),
  );
  const pitch = clamp(inp.aimPitch, PITCH_MIN, PITCH_MAX);
  sim.aimPitch += clamp(pitch - sim.aimPitch, -maxStep, maxStep);

  sim.vfx = p.vx;
  sim.vfz = p.vz;

  // 3) самоотчёт клиента (люди). Скорость валидируется МЕЖДУ репортами:
  //    |Δreport| ≤ SPEED_CAP·Δt_report + margin. Серверный DR — не якорь.
  let reportOk = false;
  if (haveReport && !sim.bot && isFinite(inp.rx!) && isFinite(inp.rz!)) {
    const nowMs = performance.now();
    const dtR = sim.repAtMs > 0 ? Math.max(0.02, (nowMs - sim.repAtMs) / 1000) : Infinity;
    const ddx = inp.rx - (isFinite(sim.repX) ? sim.repX : inp.rx);
    const ddz = inp.rz - (isFinite(sim.repZ) ? sim.repZ : inp.rz);
    const maxMove = SPEED_CAP * dtR + TELEPORT_MARGIN;
    const inBounds = Math.abs(inp.rx) < FLOOR_A + 2 && Math.abs(inp.rz) < FLOOR_B + 2;
    if (inBounds && ddx * ddx + ddz * ddz <= maxMove * maxMove) {
      sim.repX = inp.rx;
      sim.repZ = inp.rz;
      sim.repAtMs = nowMs;
      p.x = inp.rx;
      p.z = inp.rz;
      if (isFinite(inp.ry)) {
        // клиентский yaw authoritative для своей машины (мы всё равно рядом)
        p.rotY = wrapAngle(inp.ry);
      }
      if (isFinite(inp.rvx)) p.vx = inp.rvx;
      if (isFinite(inp.rvz)) p.vz = inp.rvz;
      reportOk = true;
      sim.trust = Math.min(1, sim.trust + 0.02);
    } else {
      sim.trust = Math.max(0, sim.trust - 0.2);
    }
  }

  // мягкий кламп в чашу (стенки) — для ботов/DR-фазы
  clampToArena(p);
  return reportOk;
}

export function clampToArena(p: { x: number; z: number; vx: number; vz: number }): void {
  const lim = (v: number, lim: number): number => Math.max(-lim, Math.min(lim, v));
  const nx = lim(p.x, FLOOR_A - 1.2);
  const nz = lim(p.z, FLOOR_B - 1.2);
  if (nx !== p.x) p.vx *= -0.25;
  if (nz !== p.z) p.vz *= -0.25;
  p.x = nx;
  p.z = nz;
}

export function clamp(v: number, a: number, b: number): number {
  return v < a ? a : v > b ? b : v;
}

/** Минимальное расстояние отрезка p0→p1 до сферы (c,r); t — параметр точки. */
export function segSphere(
  p0: [number, number, number], p1: [number, number, number],
  c: [number, number, number], r: number,
): { hit: boolean; t: number; at: [number, number, number] } {
  const dx = p1[0] - p0[0], dy = p1[1] - p0[1], dz = p1[2] - p0[2];
  const len2 = dx * dx + dy * dy + dz * dz;
  let t = len2 > 1e-12 ? ((c[0] - p0[0]) * dx + (c[1] - p0[1]) * dy + (c[2] - p0[2]) * dz) / len2 : 0;
  t = clamp(t, 0, 1);
  const cx = p0[0] + dx * t - c[0];
  const cy = p0[1] + dy * t - c[1];
  const cz = p0[2] + dz * t - c[2];
  const d2 = cx * cx + cy * cy + cz * cz;
  return { hit: d2 <= r * r, t, at: [c[0] + cx, c[1] + cy, c[2] + cz] };
}

export interface ProjectileSim {
  id: string;
  ownerId: string;
  x: number; y: number; z: number;
  vx: number; vy: number; vz: number;
  ttl: number;
  damage: number;
}

export function spawnProjectile(
  id: string, ownerId: string, pos: [number, number, number],
  yaw: number, pitch: number, weapon: WeaponType,
): ProjectileSim {
  const w = WEAPONS[weapon];
  const cp = Math.cos(pitch);
  const dir: [number, number, number] = [-Math.sin(yaw) * cp, Math.sin(pitch), -Math.cos(yaw) * cp];
  return {
    id, ownerId,
    x: pos[0] + dir[0] * 2.1, y: pos[1] + 0.75 + dir[1] * 2.1, z: pos[2] + dir[2] * 2.1,
    vx: dir[0] * w.speed, vy: dir[1] * w.speed, vz: dir[2] * w.speed,
    ttl: w.range, damage: w.damage,
  };
}

/**
 * Шаг снаряда: перемещение + столкновения. `targets` — сущности (возможно,
 * отмотанные). Возвращает {hitId, point} при попадании.
 */
export function stepProjectile(
  pr: ProjectileSim, dt: number,
  targets: Array<{ id: string; x: number; y: number; z: number; hp: number }>,
): { hitId: string | null; point: [number, number, number] | null; expired: boolean } {
  const px = pr.x, pz = pr.z;
  pr.x += pr.vx * dt;
  pr.y += pr.vy * dt;
  pr.z += pr.vz * dt;
  pr.ttl -= dt;
  const p0: [number, number, number] = [px, pr.y, pz];
  const p1: [number, number, number] = [pr.x, pr.y, pr.z];
  const R = PROJECTILE_TRIGGER_R + HITBOX_R;
  let bestT = Infinity;
  let bestId: string | null = null;
  let bestAt: [number, number, number] | null = null;
  for (const tg of targets) {
    if (tg.id === pr.ownerId || tg.hp <= 0) continue;
    const res = segSphere(p0, p1, [tg.x, tg.y + 0.6, tg.z], R);
    if (res.hit && res.t < bestT) {
      bestT = res.t; bestId = tg.id; bestAt = res.at;
    }
  }
  const outOfBounds =
    Math.abs(pr.x) > FLOOR_A || Math.abs(pr.z) > FLOOR_B || pr.y < 0.12 || pr.y > 14;
  if (bestId) return { hitId: bestId, point: bestAt, expired: false };
  if (outOfBounds || pr.ttl <= 0) {
    return { hitId: null, point: [pr.x, pr.y, pr.z], expired: true };
  }
  return { hitId: null, point: null, expired: false };
}

/** Хитскан: первый кандидат вдоль луча (для MG). */
export function hitscan(
  origin: [number, number, number], yaw: number, pitch: number, dist: number,
  targets: Array<{ id: string; x: number; y: number; z: number; hp: number }>,
): { hitId: string | null; end: [number, number, number] } {
  const cp = Math.cos(pitch);
  const d: [number, number, number] = [-Math.sin(yaw) * cp, Math.sin(pitch), -Math.cos(yaw) * cp];
  const end: [number, number, number] = [origin[0] + d[0] * dist, origin[1] + d[1] * dist, origin[2] + d[2] * dist];
  let best = Infinity;
  let hitId: string | null = null;
  for (const tg of targets) {
    if (tg.hp <= 0) continue;
    const res = segSphere(origin, end, [tg.x, tg.y + 0.6, tg.z], HITBOX_R);
    if (res.hit && res.t * dist < best) { best = res.t * dist; hitId = tg.id; }
  }
  return { hitId, end };
}

/** Эффекты пикапов (сервер — авторитет). */
export function applyPickup(sim: PlayerSim, type: number, player: { hp: number }): number {
  if (type === 0) player.hp = Math.min(100, player.hp + REPAIR_HEAL);
  else if (type === 1) sim.boostT = NITRO_TIME;
  else if (type === 2) sim.shieldT = SHIELD_TIME;
  return PICKUP_COOLDOWN;
}
