import { Room, Client } from "@colyseus/core";
import { BattleState, PlayerState, ProjectileState, PickupState } from "./schema";
import { ServerBotController } from "./bot/ServerBotController";

/**
 * UserCommand - Команда от клиента
 */
export interface UserCommand {
  sequenceNumber: number;
  throttle: number; // -1 to 1
  steering: number; // -1 to 1
  drift: boolean;
  boost: boolean;
  turretRotationX: number;
  turretRotationY: number;
  isShooting: boolean;
  timestamp: number;
}

/**
 * Конфигурация комнаты
 */
const ROOM_CONFIG = {
  MAX_CLIENTS: 4,
  PATCH_RATE: 20, // 20 Hz обновление состояния
  MATCHMAKING_TIMEOUT: 5000, // 5 секунд ожидания игроков
  BOT_FILL_DELAY: 1000,
  MATCH_DURATION: 300, // 5 минут
  RESPAWN_DELAY: 4000, // 4 секунды
};

/**
 * BattleRoom - Основная игровая комната
 */
export class BattleRoom extends Room<BattleState> {
  private clients: Map<Client, string> = new Map(); // Client -> PlayerId
  private bots: Map<string, ServerBotController> = new Map(); // PlayerId -> BotController
  private commands: Map<string, UserCommand[]> = new Map(); // PlayerId -> Command queue
  private matchmakingTimeout: NodeJS.Timeout | null = null;
  private matchTimer: NodeJS.Timeout | null = null;
  private botCheckInterval: NodeJS.Timeout | null = null;
  
  private pickupPositions: Array<{x: number, y: number, z: number, type: string}> = [
    {x: 0, y: 1, z: 0, type: "nitro"},
    {x: -15, y: 1, z: 15, type: "health"},
    {x: 15, y: 1, z: 15, type: "shield"},
    {x: 0, y: 1, z: -20, type: "speed"},
    {x: -20, y: 1, z: 0, type: "damage"},
    {x: 20, y: 1, z: 0, type: "nitro"},
  ];

  onCreate(options: any): void {
    console.log(`BattleRoom created with options:`, options);
    
    this.setState(new BattleState());
    this.setPatchRate(ROOM_CONFIG.PATCH_RATE);
    
    // Инициализация плюшек на карте
    this.initializePickups();
    
    // Запуск таймера ожидания игроков
    this.startMatchmakingTimeout();
    
    // Интервальная проверка для заполнения ботами
    this.botCheckInterval = setInterval(() => {
      this.checkAndFillBots();
    }, ROOM_CONFIG.BOT_FILL_DELAY);
  }

  private initializePickups(): void {
    const pickupTypes = ["nitro", "health", "shield", "speed", "damage"];
    
    this.pickupPositions.forEach((pos, index) => {
      const pickup = new PickupState();
      pickup.id = `pickup_${index}`;
      pickup.type = pos.type;
      pickup.x = pos.x;
      pickup.y = pos.y;
      pickup.z = pos.z;
      pickup.isActive = true;
      pickup.respawnTime = 0;
      
      this.state.pickups.set(pickup.id, pickup);
    });
  }

  private startMatchmakingTimeout(): void {
    this.matchmakingTimeout = setTimeout(() => {
      if (this.state.matchState === "WAITING") {
        console.log("Matchmaking timeout - filling with bots");
        this.fillRemainingSlotsWithBots();
      }
    }, ROOM_CONFIG.MATCHMAKING_TIMEOUT);
  }

  private checkAndFillBots(): void {
    if (this.state.matchState !== "WAITING" && this.state.matchState !== "PLAYING") {
      return;
    }
    
    const humanPlayers = Array.from(this.clients.keys()).length;
    const totalSlots = ROOM_CONFIG.MAX_CLIENTS;
    
    if (humanPlayers < totalSlots && this.bots.size < (totalSlots - humanPlayers)) {
      // Боты уже добавляются в onJoin через fillRemainingSlotsWithBots
    }
  }

  private fillRemainingSlotsWithBots(): void {
    const currentPlayers = this.state.players.size;
    const slotsToFill = ROOM_CONFIG.MAX_CLIENTS - currentPlayers;
    
    console.log(`Filling ${slotsToFill} slots with bots`);
    
    for (let i = 0; i < slotsToFill; i++) {
      this.addBot(`bot_${Date.now()}_${i}`);
    }
    
    // Начинаем матч когда все слоты заполнены
    if (this.state.players.size >= ROOM_CONFIG.MAX_CLIENTS) {
      this.startMatch();
    }
  }

  private addBot(botId: string): void {
    if (this.state.players.has(botId)) {
      return;
    }
    
    const playerState = new PlayerState();
    playerState.id = botId;
    playerState.isBot = true;
    playerState.hp = 100;
    playerState.maxHp = 100;
    playerState.isAlive = true;
    playerState.boost = 100;
    
    // Случайная позиция спавна
    const spawnPos = this.getSpawnPosition(this.state.spawnCount++);
    playerState.x = spawnPos.x;
    playerState.y = spawnPos.y;
    playerState.z = spawnPos.z;
    
    this.state.players.set(botId, playerState);
    
    // Создаём контроллер бота
    const botController = new ServerBotController(botId, this);
    this.bots.set(botId, botController);
    
    console.log(`Bot ${botId} added to room`);
  }

  async onJoin(client: Client, options: any): Promise<void> {
    console.log(`Player joined: ${client.sessionId}`);
    
    // Если комната полная и это бот - удаляем бота
    if (this.state.players.size >= ROOM_CONFIG.MAX_CLIENTS) {
      const botIds = Array.from(this.bots.keys());
      if (botIds.length > 0) {
        const botToRemove = botIds[0];
        this.removeBot(botToRemove);
        console.log(`Removed bot ${botToRemove} to make room for human player`);
      }
    }
    
    const playerId = client.sessionId;
    this.clients.set(client, playerId);
    this.commands.set(playerId, []);
    
    const playerState = new PlayerState();
    playerState.id = playerId;
    playerState.isBot = false;
    playerState.hp = 100;
    playerState.maxHp = 100;
    playerState.isAlive = true;
    playerState.boost = 100;
    
    // Получаем данные игрока из опций (из гаража)
    if (options.skinId) playerState.skinId = options.skinId;
    if (options.wheelId) playerState.wheelId = options.wheelId;
    if (options.weaponType) playerState.weaponType = options.weaponType;
    
    const spawnPos = this.getSpawnPosition(this.state.spawnCount++);
    playerState.x = spawnPos.x;
    playerState.y = spawnPos.y;
    playerState.z = spawnPos.z;
    
    this.state.players.set(playerId, playerState);
    
    // Отменяем таймер и заполняем оставшиеся слоты ботами если это первый игрок
    if (this.matchmakingTimeout) {
      clearTimeout(this.matchmakingTimeout);
      this.matchmakingTimeout = null;
    }
    
    // Проверяем нужно ли заполнить ботами
    if (this.state.players.size < ROOM_CONFIG.MAX_CLIENTS) {
      setTimeout(() => {
        this.fillRemainingSlotsWithBots();
      }, ROOM_CONFIG.MATCHMAKING_TIMEOUT);
    } else {
      this.startMatch();
    }
  }

  onMessage(client: Client, message: UserCommand): void {
    const playerId = this.clients.get(client);
    if (!playerId) return;
    
    const playerState = this.state.players.get(playerId);
    if (!playerState || !playerState.isAlive) return;
    
    // Добавляем команду в очередь
    const commandQueue = this.commands.get(playerId) || [];
    commandQueue.push(message);
    
    // Ограничиваем размер очереди
    if (commandQueue.length > 60) {
      commandQueue.shift();
    }
    
    this.commands.set(playerId, commandQueue);
  }

  onLeave(client: Client, consented: boolean): void {
    const playerId = this.clients.get(client);
    if (playerId) {
      console.log(`Player left: ${playerId}`);
      
      // Удаляем игрока или заменяем ботом
      const playerState = this.state.players.get(playerId);
      if (playerState && !playerState.isBot) {
        // Заменяем вышедшего игрока ботом
        this.replacePlayerWithBot(playerId);
      }
      
      this.clients.delete(client);
      this.commands.delete(playerId);
    }
    
    // Если не осталось реальных игроков - закрываем комнату
    if (this.clients.size === 0 && this.bots.size === 0) {
      console.log("No players left, closing room");
      this.disconnect();
    }
  }

  private replacePlayerWithBot(playerId: string): void {
    const playerState = this.state.players.get(playerId);
    if (!playerState) return;
    
    // Создаём бота на месте игрока
    playerState.isBot = true;
    this.state.players.set(playerId, playerState);
    
    const botController = new ServerBotController(playerId, this);
    this.bots.set(playerId, botController);
    
    console.log(`Player ${playerId} replaced with bot`);
  }

  private removeBot(botId: string): void {
    const botController = this.bots.get(botId);
    if (botController) {
      botController.dispose();
      this.bots.delete(botId);
    }
    
    const playerState = this.state.players.get(botId);
    if (playerState && playerState.isBot) {
      this.state.players.delete(botId);
    }
  }

  private startMatch(): void {
    if (this.state.matchState === "PLAYING") return;
    
    console.log("Starting match!");
    this.state.matchState = "PLAYING";
    this.state.gameTimer = ROOM_CONFIG.MATCH_DURATION;
    
    // Запускаем таймер матча
    this.matchTimer = setInterval(() => {
      this.state.gameTimer--;
      
      if (this.state.gameTimer <= 0) {
        this.endMatch();
      }
    }, 1000);
    
    // Запускаем цикл обновления ботов
    this.startBotLoop();
  }

  private startBotLoop(): void {
    // Обновляем ботов каждые 100ms
    setInterval(() => {
      this.bots.forEach((bot, botId) => {
        const playerState = this.state.players.get(botId);
        if (playerState && playerState.isAlive) {
          bot.update(100);
        }
      });
    }, 100);
  }

  private endMatch(): void {
    this.state.matchState = "FINISHED";
    
    if (this.matchTimer) {
      clearInterval(this.matchTimer);
      this.matchTimer = null;
    }
    
    // Определяем победителя
    let winner: PlayerState | null = null;
    let maxScore = 0;
    
    this.state.players.forEach((player) => {
      if (player.score > maxScore) {
        maxScore = player.score;
        winner = player;
      }
    });
    
    if (winner) {
      this.state.winnerId = winner.id;
    }
    
    console.log(`Match ended! Winner: ${this.state.winnerId}`);
    
    // Закрываем комнату через 5 секунд
    setTimeout(() => {
      this.disconnect();
    }, 5000);
  }

  getSpawnPosition(index: number): {x: number, y: number, z: number} {
    const positions = [
      {x: 0, y: 2, z: 0},
      {x: -15, y: 2, z: 15},
      {x: 15, y: 2, z: 15},
      {x: 0, y: 2, z: -20},
    ];
    return positions[index % positions.length];
  }

  processProjectileHit(projectileId: string, targetId: string, damage: number): void {
    const projectile = this.state.projectiles.get(projectileId);
    const target = this.state.players.get(targetId);
    
    if (!target || !target.isAlive) return;
    
    // Применяем урон
    target.hp -= damage;
    
    if (target.hp <= 0) {
      target.hp = 0;
      target.isAlive = false;
      
      // Находим кто убил
      if (projectile) {
        const attacker = this.state.players.get(projectile.ownerId);
        if (attacker) {
          attacker.score += 100;
          attacker.kills++;
        }
      }
      
      target.deaths++;
      
      // Респавн через RESPAWN_DELAY
      setTimeout(() => {
        this.respawnPlayer(targetId);
      }, ROOM_CONFIG.RESPAWN_DELAY);
    }
    
    // Удаляем снаряд
    this.state.projectiles.delete(projectileId);
  }

  respawnPlayer(playerId: string): void {
    const playerState = this.state.players.get(playerId);
    if (!playerState) return;
    
    const spawnPos = this.getSpawnPosition(this.state.spawnCount++);
    playerState.x = spawnPos.x;
    playerState.y = spawnPos.y;
    playerState.z = spawnPos.z;
    playerState.hp = playerState.maxHp;
    playerState.isAlive = true;
    playerState.boost = 100;
    
    console.log(`Player ${playerId} respawned`);
  }

  collectPickup(playerId: string, pickupId: string): void {
    const pickup = this.state.pickups.get(pickupId);
    const player = this.state.players.get(playerId);
    
    if (!pickup || !player || !pickup.isActive) return;
    
    // Применяем эффект плюшки
    switch (pickup.type) {
      case "nitro":
        player.boost = 100;
        break;
      case "health":
        player.hp = Math.min(player.hp + 35, player.maxHp);
        break;
      case "shield":
        player.hasShield = true;
        player.shieldEndTime = Date.now() + 6000;
        break;
      case "speed":
        player.speedMultiplier = 1.3;
        setTimeout(() => { player.speedMultiplier = 1.0; }, 5000);
        break;
      case "damage":
        player.damageMultiplier = 1.5;
        setTimeout(() => { player.damageMultiplier = 1.0; }, 5000);
        break;
    }
    
    // Деактивируем плюшку
    pickup.isActive = false;
    pickup.respawnTime = Date.now() + 10000; // 10 секунд
    
    // Респавн плюшки
    setTimeout(() => {
      pickup.isActive = true;
      pickup.respawnTime = 0;
    }, 10000);
  }

  update(deltaTime: number): void {
    // Обработка команд игроков
    this.clients.forEach((playerId, client) => {
      const commandQueue = this.commands.get(playerId);
      const playerState = this.state.players.get(playerId);
      
      if (!playerState || !playerState.isAlive || !commandQueue || commandQueue.length === 0) {
        return;
      }
      
      // Берём последнюю команду
      const latestCommand = commandQueue[commandQueue.length - 1];
      
      // Здесь должна быть логика валидации и применения движения
      // Для простоты просто обновляем позицию (в реальной игре - физика на сервере)
      
      if (latestCommand.isShooting) {
        // Создаём снаряд
        this.createProjectile(playerId, playerState);
      }
    });
    
    // Проверка щитов
    const now = Date.now();
    this.state.players.forEach((player) => {
      if (player.hasShield && now > player.shieldEndTime) {
        player.hasShield = false;
      }
    });
  }

  private createProjectile(ownerId: string, playerState: PlayerState): void {
    const projectile = new ProjectileState();
    projectile.id = `proj_${Date.now()}_${ownerId}`;
    projectile.ownerId = ownerId;
    projectile.x = playerState.x;
    projectile.y = playerState.y + 1;
    projectile.z = playerState.z;
    
    // Направление стрельбы (упрощённо - вперёд по направлению игрока)
    const speed = 120;
    projectile.vx = Math.sin(playerState.rotY) * speed;
    projectile.vy = 0;
    projectile.vz = Math.cos(playerState.rotY) * speed;
    
    projectile.damage = 15;
    projectile.createdAt = Date.now();
    projectile.lifetime = 3000;
    
    this.state.projectiles.set(projectile.id, projectile);
    
    // Автоудаление снаряда
    setTimeout(() => {
      this.state.projectiles.delete(projectile.id);
    }, projectile.lifetime);
  }

  dispose(): void {
    console.log("Disposing BattleRoom");
    
    if (this.matchmakingTimeout) {
      clearTimeout(this.matchmakingTimeout);
    }
    if (this.matchTimer) {
      clearInterval(this.matchTimer);
    }
    if (this.botCheckInterval) {
      clearInterval(this.botCheckInterval);
    }
    
    this.bots.forEach((bot) => bot.dispose());
    this.bots.clear();
    this.clients.clear();
    this.commands.clear();
  }
}
