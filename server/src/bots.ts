/**
 * ServerBotController — серверный бот с конечным автоматом (Sprint 3, ТЗ п.3).
 * Состояния: WANDER / SEEK_PICKUP / COMBAT.
 *
 * Бот управляет той же симуляцией, что и люди: его «UserCommand» генерируется
 * здесь и уходит в тот же stepPlayer — честные лимиты скорости/турели.
 */
import { PICKUP_RADIUS, edgeMargin, wrapAngle } from "./arena.js";
import type { InputFrame } from "./sim.js";

export type BotMode = "WANDER" | "SEEK_PICKUP" | "COMBAT";

export interface EnemyView {
  sid: string;
  x: number; z: number;
  vx: number; vz: number;
  hp: number;
}

export interface PickupView {
  id: number;
  type: number;      // 0 repair / 1 nitro / 2 shield
  x: number; z: number;
  cd: number;        // сек; <=0 готов
}

export interface BotWorld {
  enemies: EnemyView[];        // живые, без самого бота
  pickups: PickupView[];
}

export interface BotSelf {
  x: number; z: number;
  hp: number;
  boostT: number;
  yaw: number;         // текущий курс машины (для steer)
  aimYaw: number;      // текущий фактический yaw турели (лимитируется sim'ом)
}

const COMBAT_RADIUS = 45.0;                       // ТЗ: радиус обнаружения
const AIM_FIRE_ANGLE = (5 * Math.PI) / 180.0;     // ТЗ: выстрел при < 5°
const AIM_ERROR = (3 * Math.PI) / 180.0;          // ТЗ: погрешность ±3°
const LOW_HP = 40.0;                              // ТЗ: <40% HP → ремонт

export class ServerBotController {
  mode: BotMode = "WANDER";
  targetSid: string | null = null;
  aggroT = 0;               // сек lock на обидчике
  private wanderX = 0;
  private wanderZ = 0;
  private wanderT = 0;
  private aimErrYaw = 0;    // джиттер прицела (перекатывается на выстреле)
  private fireHold = 0.3;   // первичная «реакция»
  lastHitBy: string | null = null;  // кто ударил последним (для HUD/тестов)
  private seekPickupId: number | null = null;

  /** Реакция на полученный урон: сменить цель на обидчика (ТЗ п.3). */
  onDamaged(attackerSid: string | null): void {
    if (attackerSid) {
      this.aggroT = 5.0;
      this.targetSid = attackerSid;
      this.lastHitBy = attackerSid;
    }
  }

  update(self: BotSelf, world: BotWorld, dt: number): InputFrame {
    this.aggroT = Math.max(0, this.aggroT - dt);
    this.fireHold = Math.max(0, this.fireHold - dt);
    this.wanderT -= dt;

    const target = this.pickTarget(self, world);
    const wantHeal = self.hp < LOW_HP;
    const wantNitro = self.boostT <= 0.05;
    let pickup: PickupView | null = null;
    if (wantHeal) {
      pickup = this.nearestReadyPickup(self, world.pickups, 0)
        ?? this.nearestReadyPickup(self, world.pickups, 2);
    } else if (wantNitro) {
      pickup = this.nearestReadyPickup(self, world.pickups, 1);
    }

    let moveYaw: number;
    let throttle = 1.0;
    let fire = false;
    let aimYaw = self.aimYaw;

    if (pickup && (wantHeal || wantNitro)) {
      this.mode = "SEEK_PICKUP";
      this.seekPickupId = pickup.id;
      moveYaw = this.yawToward(self, pickup.x, pickup.z);
    } else if (target) {
      this.mode = "COMBAT";
      this.seekPickupId = null;
      moveYaw = this.combatMove(self, target);
      const shot = this.aimAndShoot(self, target);
      aimYaw = shot.aimYaw;
      fire = shot.fire;
    } else {
      this.mode = "WANDER";
      this.seekPickupId = null;
      if (this.wanderT <= 0) this.pickWanderPoint();
      moveYaw = this.yawToward(self, this.wanderX, this.wanderZ);
      // «движение с гашением скорости перед стенами» (ТЗ)
      const m = edgeMargin(self.x, self.z);
      if (m < 7.5) throttle = Math.max(0.25, m / 7.5);
    }

    return {
      throttle,
      steer: this.steerToward(self.yaw, moveYaw),
      drift: false,
      boost: false,
      fire,
      aimYaw,
      aimPitch: 0,
    };
  }

  // ── COMBAT ────────────────────────────────────────────────────────

  private pickTarget(self: { x: number; z: number }, world: BotWorld): EnemyView | null {
    // 1) «реагирует на повреждения» (ТЗ): удержание агрессии на обидчике
    if (this.aggroT > 0 && this.targetSid) {
      const t = world.enemies.find((e) => e.sid === this.targetSid && e.hp > 0);
      if (t && Math.hypot(t.x - self.x, t.z - self.z) < 80) return t;
      this.aggroT = 0;   // цель мертва/далека — снимаем агрессию
    }
    // 2) ближайший в радиусе обнаружения
    let best: EnemyView | null = null;
    let bestD = Infinity;
    for (const e of world.enemies) {
      if (e.hp <= 0) continue;
      const d = Math.hypot(e.x - self.x, e.z - self.z);
      if (d < COMBAT_RADIUS && d < bestD) { best = e; bestD = d; this.targetSid = e.sid; }
    }
    return best;
  }

  /** Держим дистанцию 12–24 м: на близкой — отход, иначе — «круги». */
  private combatMove(self: { x: number; z: number }, target: EnemyView): number {
    const dx = target.x - self.x, dz = target.z - self.z;
    const d = Math.hypot(dx, dz);
    if (d < 12) return this.yawToward(self, self.x - dx, self.z - dz);
    const px = -dz / (d || 1), pz = dx / (d || 1);
    return this.yawToward(self, target.x + px * 6, target.z + pz * 6);
  }

  /** Наводка с упреждением и выстрел при угле < 5° (ТЗ). */
  private aimAndShoot(self: { x: number; z: number; aimYaw: number }, target: EnemyView):
    { aimYaw: number; fire: boolean } {
    const dx = target.x - self.x, dz = target.z - self.z;
    const dist = Math.hypot(dx, dz) || 1;
    // упреждение по вектору скорости цели (снаряд 120 м/с)
    const lead = dist / 120.0;
    const lx = target.x + target.vx * lead;
    const lz = target.z + target.vz * lead;
    const des = Math.atan2(-(lx - self.x), -(lz - self.z));
    const err = Math.abs(wrapAngle(des - self.aimYaw));
    if (err < AIM_FIRE_ANGLE && this.fireHold <= 0) {
      // задержка реакции + реджеттер; погрешность ±3° — на каждый выстрел
      this.fireHold = 0.22 + Math.random() * 0.18;
      this.aimErrYaw = (Math.random() * 2 - 1) * AIM_ERROR;
      return { aimYaw: des + this.aimErrYaw, fire: true };
    }
    return { aimYaw: des + this.aimErrYaw, fire: false };
  }

  // ── WANDER / вспомогательное ──────────────────────────────────────

  private pickWanderPoint(): void {
    this.wanderT = 3 + Math.random() * 4;
    this.wanderX = (Math.random() * 2 - 1) * 34;
    this.wanderZ = (Math.random() * 2 - 1) * 22;
  }

  private nearestReadyPickup(
    self: { x: number; z: number }, list: PickupView[], type: number,
  ): PickupView | null {
    let best: PickupView | null = null;
    let bestD = Infinity;
    for (const p of list) {
      if (p.type !== type || p.cd > 0.5) continue;
      const d = Math.hypot(p.x - self.x, p.z - self.z);
      if (d < bestD) { best = p; bestD = d; }
    }
    return best;
  }

  private yawToward(self: { x: number; z: number }, tx: number, tz: number): number {
    return Math.atan2(-(tx - self.x), -(tz - self.z));
  }

  private steerToward(curYaw: number, yawDes: number): number {
    const err = wrapAngle(yawDes - curYaw);
    return Math.max(-1, Math.min(1, err * 2.2));
  }

  get debugState(): { mode: BotMode; target: string | null; seek: number | null; lastHitBy: string | null } {
    return { mode: this.mode, target: this.targetSid, seek: this.seekPickupId, lastHitBy: this.lastHitBy };
  }
}

export const BOT_PICKUP_RADIUS = PICKUP_RADIUS;
