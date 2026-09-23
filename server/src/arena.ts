/**
 * Геометрия/физика арены на сервере — зеркало src/arena/arena_bowl.gd и
 * arcade_vehicle.gd (Sprint 1/2). Держим константы синхронно вручную:
 * изменение в Godot => изменение здесь (контракт зафиксирован смоуками).
 */

/** Плоский пол чаши: |x| <= FLOOR_A, |z| <= FLOOR_B (полуоси, м). */
export const FLOOR_A = 52.0;
export const FLOOR_B = 36.0;
export const FILLET_R = 8.0;

/** Прямоугольник «безопасной игры» сервера: до начала скругления стены. */
export const SAFE_A = FLOOR_A - FILLET_R - 1.0;   // 43
export const SAFE_B = FLOOR_B - FILLET_R - 1.0;   // 27

/** Точки спавна (Spawn0..3 в arena_bowl.tscn). y — уровень покоя машины. */
export const SPAWNS: ReadonlyArray<readonly [number, number]> = [
  [-19, 15], [19, 15], [-19, -15], [19, -15],
];
export const CAR_REST_Y = 1.19;

/** Пикапы (main.tscn, Sprint 2): type 0 repair / 1 nitro / 2 shield. */
export const PICKUPS: ReadonlyArray<{ type: number; x: number; z: number }> = [
  { type: 1, x: 0, z: 27 },    // NitroNorth  (в Godot z=27 == «север»)
  { type: 1, x: 0, z: -27 },   // NitroSouth
  { type: 0, x: -26, z: 0 },   // RepairWest
  { type: 0, x: 26, z: 0 },    // RepairEast
  { type: 2, x: 0, z: 0 },     // ShieldCenter
];

/* ── Движок машины: упрощённая (2D-кинематика) копия arcade_vehicle.gd ── */
export const MAX_SPEED = 45.0;         // м/с, продольный лимит (ТЗ)
export const ACCEL = 13.3;             // engine_force 80 Н / mass 6 кг
export const REVERSE_MAX = 12.0;
export const BRAKE_DECEL = 20.0;
export const DRAG = 1.2;               // экспоненциальное торможение накатом
export const WHEELBASE = 2.7;          // м, велосипедная модель
export const STEER_LIMIT = 0.6109;     // рад (35°)
export const STEER_KEEP_HIGH = 0.35;   // доля лимита на максимуме

/* ── Оружие/бой: зеркало base_weapon/projectile/health_component ── */
export const WEAPONS = {
  cannon: { fireRate: 0.15, damage: 15.0, speed: 120.0, range: 3.0, hitscan: false },
  mg: { fireRate: 0.07, damage: 6.0, speed: 0, range: 160.0, hitscan: true },
} as const;
export type WeaponType = keyof typeof WEAPONS;

export const PROJECTILE_TRIGGER_R = 0.9;  // oversized-сфера снаряда (ТЗ)
export const HITBOX_R = 2.2;              // сфера-аппроксимация бокса 2.3×4.2
export const MAX_HEALTH = 100.0;
export const RESPAWN_DELAY = 4.0;         // с (ТЗ)
export const REPAIR_HEAL = 35.0;          // ТЗ
export const SHIELD_TIME = 6.0;           // с (ТЗ)
export const NITRO_TIME = 4.0;            // с ускоренного режима
export const PICKUP_RADIUS = 2.8;
export const PICKUP_COOLDOWN = 10.0;      // с (ТЗ)

/* ── Турель/боты ── */
export const TURRET_SPEED = 12.0;         // рад/с (ТЗ, и для ботов — честный лимит)
export const PITCH_MIN = (-10 * Math.PI) / 180.0;
export const PITCH_MAX = (30 * Math.PI) / 180.0;

/** Зеркало wrapf(x,-PI,PI). */
export function wrapAngle(a: number): number {
  return Math.atan2(Math.sin(a), Math.cos(a));
}

/** Дистанция до «безопасной стены» по осям (для снижения скорости ИИ). */
export function edgeMargin(x: number, z: number): number {
  return Math.min(SAFE_A - Math.abs(x), SAFE_B - Math.abs(z));
}
