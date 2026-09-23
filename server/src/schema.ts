/**
 * Colyseus-схемы (Sprint 3, ТЗ п.1). Поля PlayerState/BattleState — ровно
 * контракт ТЗ (+ расширенные name/shieldT/boostT/aimYaw/aimPitch — см.
 * docs/sprint3_report.md: репликация щита/нитро/турели нужна HUD, ботам и
 * интерполяции чужих машин).
 */
import { schema, t } from "@colyseus/schema";

/** Снаряд: состояние в мире сервера. Визуал на клиентах — по этим данным. */
export const ProjectileState = schema(
  {
    ownerId: t.string().default(""),
    x: t.number().default(0),
    y: t.number().default(0),
    z: t.number().default(0),
    vx: t.number().default(0),
    vy: t.number().default(0),
    vz: t.number().default(0),
    damage: t.number().default(0),
    hitscan: t.boolean().default(false),
  },
  "ProjectileState",
);

/** Пикап на сервере — источник истины для кулдаунов/эффектов. */
export const PickupState = schema(
  {
    type: t.uint8().default(0),   // 0 repair / 1 nitro / 2 shield (enum PickupBase)
    x: t.number().default(0),
    z: t.number().default(0),
    cd: t.number().default(0),    // сек до готовности (0 — готов)
  },
  "PickupState",
);

export const PlayerState = schema(
  {
    id: t.string().default(""),
    // ── трансформ/движение (контракт ТЗ) ──
    x: t.number().default(0),
    y: t.number().default(0),
    z: t.number().default(0),
    rotX: t.number().default(0),
    rotY: t.number().default(0),      // yaw — главный на плоском полу
    rotZ: t.number().default(0),
    vx: t.number().default(0),
    vy: t.number().default(0),
    vz: t.number().default(0),
    // ── бой ──
    hp: t.number().default(100),
    score: t.uint32().default(0),
    isBot: t.boolean().default(false),
    weaponType: t.string().default("cannon"),
    // ── расширенные (задокументированы) ──
    name: t.string().default(""),
    shieldT: t.number().default(0),   // сек щита осталось (поглощает урон)
    boostT: t.number().default(0),    // сек нитро осталось (×1.5 лимит)
    aimYaw: t.number().default(0),    // фактический yaw турели (чужие анимации)
    aimPitch: t.number().default(0),
  },
  "PlayerState",
);

export const BattleState = schema(
  {
    players: t.map(PlayerState),
    projectiles: t.map(ProjectileState),
    pickups: t.map(PickupState),
    gameTimer: t.number().default(0),
    matchState: t.string().default("WAITING"),   // WAITING | PLAYING | FINISHED
    winnerId: t.string().default(""),
  },
  "BattleState",
);

/**
 * UserCommand (ТЗ п.2): управление + seq. Позиция/скорость — «r*»:
 * самоотчёт клиента для trust-but-validate (см. sim.stepPlayer).
 */
export const UserCommand = schema(
  {
    seq: t.uint32().default(0),
    throttle: t.number().default(0),
    steer: t.number().default(0),
    drift: t.boolean().default(false),
    boost: t.boolean().default(false),
    fire: t.boolean().default(false),
    aimYaw: t.number().default(0),
    aimPitch: t.number().default(0),
    // самоотчёт предсказанной физики клиента
    rx: t.number().default(0),
    ry: t.number().default(0),        // yaw (ось Y машины)
    rz: t.number().default(0),
    rvx: t.number().default(0),
    rvz: t.number().default(0),
  },
  "UserCommand",
);
