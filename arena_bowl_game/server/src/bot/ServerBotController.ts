import { PlayerState } from "../schema";
import { BattleRoom } from "../BattleRoom";

/**
 * Конечный автомат (FSM) для бота
 */
enum BotState {
  WANDER = "WANDER",
  SEEK_PICKUP = "SEEK_PICKUP",
  COMBAT = "COMBAT",
  FLEE = "FLEE"
}

/**
 * ServerBotController - Контроллер бота на сервере
 * Управляет поведением бота через FSM
 */
export class ServerBotController {
  private botId: string;
  private room: BattleRoom;
  private state: BotState = BotState.WANDER;
  private targetId: string | null = null;
  private wanderDirection: number = 0;
  private wanderTimer: number = 0;
  private shootTimer: number = 0;
  private stateChangeTimer: number = 0;
  
  // Параметры поведения
  private readonly DETECTION_RADIUS = 45.0;
  private readonly ATTACK_RADIUS = 30.0;
  private readonly PICKUP_PRIORITY_HP = 40; // Если HP < 40% ищем аптечку
  private readonly AIM_ERROR_DEGREES = 3.0;
  private readonly SHOOT_ANGLE_THRESHOLD = 5.0;
  
  constructor(botId: string, room: BattleRoom) {
    this.botId = botId;
    this.room = room;
    this.wanderDirection = Math.random() * Math.PI * 2;
  }

  /**
   * Обновление состояния бота
   * @param deltaTime Время в миллисекундах с последнего обновления
   */
  update(deltaTime: number): void {
    const botState = this.room.state.players.get(this.botId);
    if (!botState || !botState.isAlive) return;
    
    this.stateChangeTimer += deltaTime;
    
    // Обновляем состояние FSM
    this.updateFSM(botState, deltaTime);
    
    // Выполняем действия согласно состоянию
    switch (this.state) {
      case BotState.WANDER:
        this.doWander(botState, deltaTime);
        break;
      case BotState.SEEK_PICKUP:
        this.doSeekPickup(botState, deltaTime);
        break;
      case BotState.COMBAT:
        this.doCombat(botState, deltaTime);
        break;
      case BotState.FLEE:
        this.doFlee(botState, deltaTime);
        break;
    }
  }

  /**
   * Обновление конечного автомата
   */
  private updateFSM(botState: PlayerState, deltaTime: number): void {
    // Проверяем приоритеты состояний
    
    // 1. Если мало HP - ищем аптечку или убегаем
    const hpPercent = (botState.hp / botState.maxHp) * 100;
    if (hpPercent < 20) {
      const healthPickup = this.findNearestPickup("health");
      if (healthPickup) {
        this.changeState(BotState.SEEK_PICKUP, "health");
        return;
      } else {
        this.changeState(BotState.FLEE);
        return;
      }
    }
    
    // 2. Если мало буста - ищем нитро
    if (botState.boost < 20) {
      const nitroPickup = this.findNearestPickup("nitro");
      if (nitroPickup) {
        this.changeState(BotState.SEEK_PICKUP, "nitro");
        return;
      }
    }
    
    // 3. Если есть враг в радиусе - атакуем
    const nearestEnemy = this.findNearestEnemy(botState);
    if (nearestEnemy) {
      this.changeState(BotState.COMBAT, nearestEnemy.id);
      return;
    }
    
    // 4. Иначе блуждаем
    this.changeState(BotState.WANDER);
  }

  /**
   * Смена состояния FSM
   */
  private changeState(newState: BotState, targetId?: string): void {
    if (this.state !== newState) {
      this.state = newState;
      this.targetId = targetId || null;
      this.stateChangeTimer = 0;
      
      if (newState === BotState.WANDER) {
        this.wanderDirection = Math.random() * Math.PI * 2;
      }
    }
  }

  /**
   * Поведение: Блуждание
   */
  private doWander(botState: PlayerState, deltaTime: number): void {
    // Меняем направление каждые 2-4 секунды
    this.wanderTimer += deltaTime;
    if (this.wanderTimer > 2000 + Math.random() * 2000) {
      this.wanderDirection = Math.random() * Math.PI * 2;
      this.wanderTimer = 0;
    }
    
    // Движение вперёд с небольшим поворотом
    const speed = 0.6; // Нормализованная скорость
    botState.x += Math.sin(this.wanderDirection) * speed * (deltaTime / 1000) * 20;
    botState.z += Math.cos(this.wanderDirection) * speed * (deltaTime / 1000) * 20;
    botState.rotY = this.wanderDirection;
    
    // Иногда стреляем наугад
    if (Math.random() < 0.01) {
      this.tryShoot(botState);
    }
  }

  /**
   * Поведение: Поиск плюшки
   */
  private doSeekPickup(botState: PlayerState, deltaTime: number): void {
    if (!this.targetId) {
      this.changeState(BotState.WANDER);
      return;
    }
    
    const pickup = this.room.state.pickups.get(this.targetId);
    if (!pickup || !pickup.isActive) {
      this.changeState(BotState.WANDER);
      return;
    }
    
    // Вычисляем направление к плюшке
    const dx = pickup.x - botState.x;
    const dz = pickup.z - botState.z;
    const distance = Math.sqrt(dx * dx + dz * dz);
    
    if (distance < 2.0) {
      // Достигли плюшки - собираем
      this.room.collectPickup(this.botId, this.targetId);
      this.changeState(BotState.WANDER);
      return;
    }
    
    // Движение к плюшке
    const targetAngle = Math.atan2(dx, dz);
    botState.rotY = this.smoothRotate(botState.rotY, targetAngle, deltaTime);
    
    const speed = 0.8;
    botState.x += Math.sin(targetAngle) * speed * (deltaTime / 1000) * 25;
    botState.z += Math.cos(targetAngle) * speed * (deltaTime / 1000) * 25;
  }

  /**
   * Поведение: Бой
   */
  private doCombat(botState: PlayerState, deltaTime: number): void {
    if (!this.targetId) {
      this.changeState(BotState.WANDER);
      return;
    }
    
    const target = this.room.state.players.get(this.targetId);
    if (!target || !target.isAlive) {
      this.changeState(BotState.WANDER);
      return;
    }
    
    const dx = target.x - botState.x;
    const dz = target.z - botState.z;
    const distance = Math.sqrt(dx * dx + dz * dz);
    
    // Если слишком далеко - приближаемся
    if (distance > this.ATTACK_RADIUS) {
      const targetAngle = Math.atan2(dx, dz);
      botState.rotY = this.smoothRotate(botState.rotY, targetAngle, deltaTime);
      
      const speed = 0.9;
      botState.x += Math.sin(targetAngle) * speed * (deltaTime / 1000) * 30;
      botState.z += Math.cos(targetAngle) * speed * (deltaTime / 1000) * 30;
    }
    
    // Если в радиусе атаки - стреляем
    if (distance < this.ATTACK_RADIUS) {
      // Поворот башни к цели с погрешностью
      const targetAngle = Math.atan2(dx, dz);
      const aimError = (Math.random() - 0.5) * 2 * (this.AIM_ERROR_DEGREES * Math.PI / 180);
      botState.rotY = this.smoothRotate(botState.rotY, targetAngle + aimError, deltaTime);
      
      // Проверяем угол для выстрела
      const angleDiff = Math.abs(this.normalizeAngle(botState.rotY - targetAngle));
      if (angleDiff < (this.SHOOT_ANGLE_THRESHOLD * Math.PI / 180)) {
        this.tryShoot(botState);
      }
    }
  }

  /**
   * Поведение: Побег
   */
  private doFlee(botState: PlayerState, deltaTime: number): void {
    const nearestEnemy = this.findNearestEnemy(botState);
    if (!nearestEnemy) {
      this.changeState(BotState.WANDER);
      return;
    }
    
    // Движение ОТ врага
    const dx = botState.x - nearestEnemy.x;
    const dz = botState.z - nearestEnemy.z;
    const fleeAngle = Math.atan2(dx, dz);
    
    botState.rotY = this.smoothRotate(botState.rotY, fleeAngle, deltaTime);
    
    const speed = 1.0; // Максимальная скорость
    botState.x += Math.sin(fleeAngle) * speed * (deltaTime / 1000) * 35;
    botState.z += Math.cos(fleeAngle) * speed * (deltaTime / 1000) * 35;
  }

  /**
   * Попытка выстрела
   */
  private tryShoot(botState: PlayerState): void {
    this.shootTimer += 16; // Примерно 60 FPS
    
    const fireRate = 667; // 0.667 секунды между выстрелами (как в base_weapon.gd)
    if (this.shootTimer >= fireRate) {
      // Создаём снаряд через комнату
      // В реальной игре здесь будет отправка команды на создание снаряда
      console.log(`Bot ${this.botId} shooting!`);
      this.shootTimer = 0;
    }
  }

  /**
   * Поиск ближайшего врага
   */
  private findNearestEnemy(botState: PlayerState): PlayerState | null {
    let nearest: PlayerState | null = null;
    let nearestDistance = this.DETECTION_RADIUS;
    
    this.room.state.players.forEach((player) => {
      if (player.id === this.botId || !player.isAlive) return;
      
      const dx = player.x - botState.x;
      const dz = player.z - botState.z;
      const distance = Math.sqrt(dx * dx + dz * dz);
      
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = player;
      }
    });
    
    return nearest;
  }

  /**
   * Поиск ближайшей плюшки указанного типа
   */
  private findNearestPickup(type: string): string | null {
    let nearestId: string | null = null;
    let nearestDistance = Infinity;
    
    const botState = this.room.state.players.get(this.botId);
    if (!botState) return null;
    
    this.room.state.pickups.forEach((pickup) => {
      if (!pickup.isActive || pickup.type !== type) return;
      
      const dx = pickup.x - botState.x;
      const dz = pickup.z - botState.z;
      const distance = Math.sqrt(dx * dx + dz * dz);
      
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestId = pickup.id;
      }
    });
    
    return nearestId;
  }

  /**
   * Плавный поворот угла
   */
  private smoothRotate(current: number, target: number, deltaTime: number): number {
    const rotationSpeed = 5.0; // rad/s
    let diff = this.normalizeAngle(target - current);
    
    const maxRotation = rotationSpeed * (deltaTime / 1000);
    if (Math.abs(diff) > maxRotation) {
      diff = Math.sign(diff) * maxRotation;
    }
    
    return this.normalizeAngle(current + diff);
  }

  /**
   * Нормализация угла в диапазон [-PI, PI]
   */
  private normalizeAngle(angle: number): number {
    while (angle > Math.PI) angle -= Math.PI * 2;
    while (angle < -Math.PI) angle += Math.PI * 2;
    return angle;
  }

  /**
   * Очистка ресурсов
   */
  dispose(): void {
    // Nothing to clean up for now
  }
}
