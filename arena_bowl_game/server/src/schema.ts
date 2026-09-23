import { Schema, type, MapSchema } from "@colyseus/schema";

/**
 * PlayerState - Состояние одного игрока/бота
 * Синхронизируется со всеми клиентами
 */
export class PlayerState extends Schema {
  @type("string") id: string = "";
  
  @type("number") x: number = 0;
  @type("number") y: number = 0;
  @type("number") z: number = 0;
  
  @type("number") rotX: number = 0;
  @type("number") rotY: number = 0;
  @type("number") rotZ: number = 0;
  
  @type("number") vx: number = 0;
  @type("number") vy: number = 0;
  @type("number") vz: number = 0;
  
  @type("number") hp: number = 100;
  @type("number") maxHp: number = 100;
  @type("number") score: number = 0;
  @type("number") kills: number = 0;
  @type("number") deaths: number = 0;
  
  @type("boolean") isBot: boolean = false;
  @type("string") weaponType: string = "projectile";
  @type("number") teamId: number = 0;
  
  @type("boolean") isAlive: boolean = true;
  @type("number") boost: number = 100;
  @type("string") skinId: string = "default";
  @type("string") wheelId: string = "default";
  
  // Временные баффы
  @type("number") speedMultiplier: number = 1.0;
  @type("number") damageMultiplier: number = 1.0;
  @type("boolean") hasShield: boolean = false;
  @type("number") shieldEndTime: number = 0;
}

/**
 * ProjectileState - Состояние снаряда
 */
export class ProjectileState extends Schema {
  @type("string") id: string = "";
  @type("string") ownerId: string = "";
  @type("number") x: number = 0;
  @type("number") y: number = 0;
  @type("number") z: number = 0;
  @type("number") vx: number = 0;
  @type("number") vy: number = 0;
  @type("number") vz: number = 0;
  @type("number") damage: number = 15;
  @type("number") createdAt: number = 0;
  @type("number") lifetime: number = 3000; // ms
  @type("boolean") isSplash: boolean = false;
  @type("number") splashRadius: number = 2.0;
}

/**
 * PickupState - Состояние плюшки на карте
 */
export class PickupState extends Schema {
  @type("string") id: string = "";
  @type("string") type: string = "nitro"; // nitro, health, shield, speed, damage
  @type("number") x: number = 0;
  @type("number") y: number = 0;
  @type("number") z: number = 0;
  @type("boolean") isActive: boolean = true;
  @type("number") respawnTime: number = 0; // timestamp когда появится
}

/**
 * BattleState - Полное состояние боя
 */
export class BattleState extends Schema {
  @type({ map: PlayerState }) players: MapSchema<PlayerState> = new MapSchema<PlayerState>();
  @type({ map: ProjectileState }) projectiles: MapSchema<ProjectileState> = new MapSchema<ProjectileState>();
  @type({ map: PickupState }) pickups: MapSchema<PickupState> = new MapSchema<PickupState>();
  
  @type("number") gameTimer: number = 0;
  @type("number") matchDuration: number = 300; // 5 минут
  
  @type("string") matchState: string = "WAITING"; // WAITING, PLAYING, FINISHED
  @type("string") winnerId: string = "";
  
  @type("number") spawnCount: number = 0;
}
