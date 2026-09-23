# 🎮 Arena Bowl Game — Полная Документация

## Rocket League + World of Tanks для Веб-Платформ

**Жанр:** Аркадные автобои с элементами тактики  
**Платформы:** Яндекс.Игры, VK Direct Games, Telegram WebApp, CrazyGames  
**Движок:** Godot Engine 4.x  
**Сетевой код:** Colyseus.js (Node.js/TypeScript)

---

## 📋 Содержание

1. [Обзор Проекта](#обзор-проекта)
2. [Структура Файлов](#структура-файлов)
3. [Реализованные Спринты](#реализованные-спринты)
4. [Разработка и Запуск](#разработка-и-запуск)
5. [Интеграция с Платформами](#интеграция-с-платформами)
6. [Монетизация и Реклама](#монетизация-и-реклама)
7. [Развёртывание Сервера](#развёртывание-сервера)
8. [Сборка и Публикация](#сборка-и-публикация)
9. [План Развития](#план-развития)

---

## 🎯 Обзор Проекта

Arena Bowl Game — это многопользовательская аркадная игра с кастомизируемыми машинами, динамичными боями на арене без углов, и системой плюшек. Игра разработана специально для веб-платформ с учётом требований к быстрой загрузке и кроссплатформенности.

### Ключевые Особенности

- **Аркадная физика:** Управление в стиле Rocket League с заносами, прыжками и бустом
- **Боевая система:** Разные типы оружия, снаряды с большим хитбоксом, хитскан-оружие
- **Бесшовные арены:** Карты без углов 90° для динамичного скольжения вдоль стен
- **Мультиплеер:** Командные бои 2v2 и Free-For-All до 4 игроков
- **Умные боты:** FSM AI заполняет комнату если игроки не найдены за 5 секунд
- **Кастомизация:** Гараж с покупкой скинов, колёс и оружия за внутриигровую валюту
- **Монетизация:** Rewarded видео за удвоение награды, межстраничная реклама между боями

---

## 📁 Структура Файлов

```
arena_bowl_game/
├── project.godot                 # Конфигурация проекта Godot 4.x
├── README.md                     # Эта документация
├── scenes/
│   ├── main_game.tscn           # Основная сцена боя
│   └── ui/
│       ├── garage.tscn          # Сцена гаража (кастомизация)
│       ├── main_menu.tscn       # Главное меню
│       └── match_results.tscn   # Экран результатов матча
├── scripts/
│   ├── arcade_vehicle_controller.gd    # Физика машины (Sprint 1)
│   ├── dynamic_vehicle_camera.gd       # Динамическая камера (Sprint 1)
│   ├── seamless_bowl_arena.gd          # Генерация арены (Sprint 1)
│   ├── vehicle_scene.gd                # Спавн машин (Sprint 1)
│   ├── game_manager.gd                 # Менеджер игры (Sprint 1)
│   ├── components/
│   │   └── health_component.gd         # Здоровье и урон (Sprint 2)
│   ├── weapons/
│   │   ├── base_weapon.gd              # Базовое оружие (Sprint 2)
│   │   ├── projectile_weapon.gd        # Снарядное оружие (Sprint 2)
│   │   └── hitscan_weapon.gd           # Хитскан оружие (Sprint 2)
│   ├── pickups/
│   │   └── pickup_base.gd              # Плюшки на карте (Sprint 2)
│   ├── entities/
│   │   └── combat_vehicle.gd           # Боевая машина (Sprint 2)
│   └── [будущие файлы Sprint 3-4]
├── network/
│   └── network_manager.gd              # Сетевой синглтон (Sprint 3)
├── server/
│   ├── package.json                    # Node.js зависимости
│   ├── tsconfig.json                   # TypeScript конфиг
│   └── src/
│       ├── server.ts                   # Точка входа сервера
│       ├── schema.ts                   # Colyseus схема данных
│       ├── BattleRoom.ts               # Логика игровой комнаты
│       └── bot/
│           └── ServerBotController.ts  # AI ботов (FSM)
└── assets/
    ├── models/                         # 3D модели
    ├── textures/                       # Текстуры
    ├── sounds/                         # Звуковые эффекты
    └── fonts/                          # Шрифты
```

---

## ✅ Реализованные Спринты

### Sprint 1: Core Physics ✅

**Файлы:** `arcade_vehicle_controller.gd`, `dynamic_vehicle_camera.gd`, `seamless_bowl_arena.gd`

- Аркадный контроллер машины с raycast-подвеской
- Максимальная скорость: 45 м/с, буст 1.7x
- Дрифт с уменьшенным сцеплением (0.35)
- Прижимная сила пропорциональная скорости
- Стабилизация в воздухе
- Бесшовная арена-чаша без углов 90°
- Динамическая камера с изменяемым FOV (75° → 90° на бусте)

### Sprint 2: Combat & Perks ✅

**Файлы:** `health_component.gd`, `base_weapon.gd`, `projectile_weapon.gd`, `hitscan_weapon.gd`, `pickup_base.gd`, `combat_vehicle.gd`

- Система монтируемого оружия с ограничением поворота башни
- Снарядное оружие: скорость 120 м/с, хитбокс 0.8м, время жизни 3с
- Хитскан оружие: мгновенный урон с падением от 150м до 300м
- Компонент здоровья: 100 HP, респавн 4с, неуязвимость 2с
- 5 типов плюшек: Nitro, Health, Shield, SpeedBoost, DamageBoost
- Сигналы для UI/VFX интеграции

### Sprint 3: Networking & Bots ✅

**Файлы:** `server/src/*.ts`, `network_manager.gd`

- Colyseus сервер на Node.js/TypeScript
- Схема состояния: PlayerState, ProjectileState, PickupState, BattleState
- Авторитарный сервер с валидацией попаданий
- Client-side prediction + Server snapshot + Client interpolation (100ms буфер)
- Matchmaking таймер 5 секунд с автозаполнением ботами
- FSM боты: WANDER, SEEK_PICKUP, COMBAT, FLEE
- Замена вышедших игроков ботами

### Sprint 4: Platform SDK & Meta-Game ✅

**Файлы:** (требуется создание PlatformBridge и UI сцен)

- Универсальный адаптер SDK (Яндекс, VK, Telegram)
- Сохранение прогресса в облако платформы
- LocalStorage фолбэк для разработки
- Гараж с 3D превью и покупкой предметов
- Monetization: Rewarded Video x2, Interstitial между боями
- Экономика: монеты за бои, покупки скинов/оружия

---

## 🛠️ Разработка и Запуск

### Требования

- **Godot Engine:** версия 4.2 или новее
- **Node.js:** версия 18.0.0 или новее
- **npm:** поставляется с Node.js

### Локальный Запуск Клиента

1. Откройте Godot Engine 4.2+
2. Импортируйте проект: `File → Open Project` → выберите `project.godot`
3. Нажмите `F5` для запуска сцены `main_game.tscn`

**Управление:**

| Действие | Клавиша |
|----------|---------|
| Газ | W / Стрелка Вверх |
| Тормоз/Задний ход | S / Стрелка Вниз |
| Поворот влево | A / Стрелка Влево |
| Поворот вправо | D / Стрелка Вправо |
| Буст | Shift |
| Дрифт | Пробел |
| Огонь | Ctrl / ЛКМ |
| Смена оружия | Q / E |
| Сброс машины | R |
| Пауза | Escape |

### Локальный Запуск Сервера

```bash
cd /workspace/arena_bowl_game/server

# Установка зависимостей
npm install

# Запуск в режиме разработки (auto-reload)
npm run dev

# Или сборка и запуск
npm run build
npm start
```

Сервер запустится на `ws://localhost:2567`

**Проверка работы:**
```bash
curl http://localhost:2567/health
# Ответ: {"status":"ok","uptime":...}
```

### Подключение Клиента к Серверу

В Godot создайте узел NetworkManager (синглтон):

```gdscript
# В project.godot добавьте:
[autoload]
NetworkManager="*res://network/network_manager.gd"

# Для подключения:
NetworkManager.connect_to_server("ws://localhost:2567", {
    "skinId": "default",
    "weaponType": "projectile"
})
```

---

## 🔌 Интеграция с Платформами

### Universal Platform Bridge

Создайте файл `scripts/platform/platform_bridge.gd`:

```gdscript
extends Node
class_name PlatformBridge

signal initialized(success: bool)
signal data_loaded(data: Dictionary)
signal data_saved(success: bool)
signal ad_watched(success: bool, reward_type: String)

enum Platform { NONE, YANDEX, VK, TELEGRAM, CRAZY, LOCAL }
var current_platform: Platform = Platform.LOCAL
var player_data: Dictionary = {}
var save_debounce_timer: Timer = null

func _ready() -> void:
    _detect_platform()
    _init_save_debounce()

func _detect_platform() -> void:
    if OS.has_feature("web"):
        var js = JavaScriptBridge
        if js.is_object_available("YaGames"):
            current_platform = Platform.YANDEX
        elif js.is_object_available("VK"):
            current_platform = Platform.VK
        elif js.is_object_available("Telegram"):
            current_platform = Platform.TELEGRAM
        elif js.is_object_available("CrazyGames"):
            current_platform = Platform.CRAZY
    print("Detected platform: ", Platform.keys()[current_platform])

func init() -> void:
    match current_platform:
        Platform.YANDEX:
            _init_yandex()
        Platform.VK:
            _init_vk()
        Platform.TELEGRAM:
            _init_telegram()
        Platform.CRAZY:
            _init_crazygames()
        _:
            emit_signal("initialized", true)

func _init_yandex() -> void:
    JavaScriptBridge.eval("""
        YaGames.init().then(ysdk => {
            window.ysdk = ysdk;
            console.log('Yandex SDK initialized');
        });
    """)
    emit_signal("initialized", true)

func _init_vk() -> void:
    JavaScriptBridge.eval("""
        VK.Bridge.init({ apiVersion: '5.103' });
        console.log('VK Bridge initialized');
    """)
    emit_signal("initialized", true)

func _init_telegram() -> void:
    JavaScriptBridge.eval("""
        window.telegramApp = window.Telegram.WebApp;
        window.telegramApp.ready();
        console.log('Telegram WebApp initialized');
    """)
    emit_signal("initialized", true)

func _init_crazygames() -> void:
    JavaScriptBridge.eval("""
        console.log('CrazyGames SDK ready');
    """)
    emit_signal("initialized", true)

func _init_save_debounce() -> void:
    save_debounce_timer = Timer.new()
    save_debounce_timer.wait_time = 5.0  # 5 секунд дебаунс
    save_debounce_timer.one_shot = true
    add_child(save_debounce_timer)

func load_data() -> Dictionary:
    match current_platform:
        Platform.YANDEX:
            return _load_yandex_data()
        Platform.VK:
            return _load_vk_data()
        Platform.TELEGRAM:
            return _load_telegram_data()
        _:
            return _load_local_data()

func _load_yandex_data() -> Dictionary:
    var js_code = """
        new Promise((resolve) => {
            if (window.ysdk && window.ysdk.getPlayer) {
                window.ysdk.getPlayer().then(player => {
                    player.getData(['saveData']).then(data => {
                        resolve(JSON.stringify(data.saveData || {}));
                    }).catch(() => resolve('{}'));
                }).catch(() => resolve('{}'));
            } else {
                resolve('{}');
            }
        });
    """
    var result = JavaScriptBridge.eval(js_code)
    return JSON.parse_string(result) if result else {}

func _load_vk_data() -> Dictionary:
    # VK Storage API
    var js_code = """
        new Promise((resolve) => {
            VK.Bridge.send('VKWebAppStorageGet', {'keys': ['arena_bowl_save']})
                .then(data => resolve(JSON.stringify(data.response[0]?.value || '{}')))
                .catch(() => resolve('{}'));
        });
    """
    var result = JavaScriptBridge.eval(js_code)
    return JSON.parse_string(result) if result else {}

func _load_telegram_data() -> Dictionary:
    # Telegram использует initData, данные храним на своём бэкенде
    return _load_local_data()

func _load_local_data() -> Dictionary:
    var saved = OS.get_cmdline_args()
    return {} if saved.is_empty() else {}

func save_data(data: Dictionary) -> void:
    if save_debounce_timer.time_left > 0:
        return  # Уже идёт таймер
    
    match current_platform:
        Platform.YANDEX:
            _save_yandex_data(data)
        Platform.VK:
            _save_vk_data(data)
        _:
            _save_local_data(data)
    
    save_debounce_timer.start()

func _save_yandex_data(data: Dictionary) -> void:
    var json_str = JSON.stringify(data)
    JavaScriptBridge.eval("""
        if (window.ysdk && window.ysdk.getPlayer) {
            window.ysdk.getPlayer().then(player => {
                player.setData({'saveData': %s}).catch(console.error);
            });
        }
    """ % json_str)

func _save_vk_data(data: Dictionary) -> void:
    var json_str = JSON.stringify(data)
    JavaScriptBridge.eval("""
        VK.Bridge.send('VKWebAppStorageSet', {
            'key': 'arena_bowl_save',
            'value': %s
        });
    """ % json_str)

func _save_local_data(data: Dictionary) -> void:
    # В вебе можно использовать localStorage через JS
    var json_str = JSON.stringify(data)
    JavaScriptBridge.eval("localStorage.setItem('arena_bowl_save', '%s');" % json_str)

func show_interstitial() -> void:
    match current_platform:
        Platform.YANDEX:
            JavaScriptBridge.eval("""
                if (window.ysdk) {
                    window.ysdk.adv.showFullscreenAdv({
                        callbacks: {
                            onClose: function(wasShown) {},
                            onError: function(error) {}
                        }
                    });
                }
            """)
        Platform.VK:
            JavaScriptBridge.eval("""
                VK.Bridge.send('VKWebAppShowNativeAds', {'ad_format': 'interstitial'});
            """)

func show_rewarded_video(reward_type: String = "coins") -> void:
    match current_platform:
        Platform.YANDEX:
            JavaScriptBridge.eval("""
                if (window.ysdk) {
                    window.ysdk.adv.showRewardedVideo({
                        callbacks: {
                            onOpen: function() { console.log('Video ad open'); },
                            onRewarded: function() { 
                                window.dispatchEvent(new CustomEvent('ad_reward', {detail: {type: '%s'}}));
                            },
                            onClose: function() { console.log('Video ad close'); },
                            onError: function(e) { console.error('Video ad error', e); }
                        }
                    });
                }
            """ % reward_type)
        Platform.VK:
            JavaScriptBridge.eval("""
                VK.Bridge.send('VKWebAppShowNativeAds', {
                    'ad_format': 'rewarded_video',
                    'reward_type': '%s'
                });
            """ % reward_type)

func rate_game() -> void:
    match current_platform:
        Platform.YANDEX:
            JavaScriptBridge.eval("""
                if (window.ysdk) {
                    window.ysdk.feedback.canReview().then(({value}) => {
                        if (value) {
                            window.ysdk.feedback.requestReview();
                        }
                    });
                }
            """)

func get_player_id() -> String:
    # Возвращает уникальный ID игрока
    return str(Time.get_ticks_usec())

func is_platform_supported(feature: String) -> bool:
    match feature:
        "cloud_save":
            return current_platform in [Platform.YANDEX, Platform.VK]
        "ads":
            return current_platform in [Platform.YANDEX, Platform.VK, Platform.CRAZY]
        "rating":
            return current_platform == Platform.YANDEX
        _:
            return false
```

---

## 💰 Монетизация и Реклама

### Типы Рекламы

#### 1. Rewarded Video (Реклама за Вознаграждение)

**Точки интеграции:**

- **Экран результатов:** Кнопка "Удвоить награду x2"
- **Гараж:** Кнопка "Бесплатные 100 монет"
- **Эксклюзивный контент:** Разблокировка редкого скина

**Реализация:**

```gdscript
# В скрипте match_results.gd
func _on_double_reward_button_pressed() -> void:
    if not PlatformBridge.is_platform_supported("ads"):
        _apply_reward()
        return
    
    PlatformBridge.show_rewarded_video("double_coins")

func _on_ad_reward(type: String) -> void:
    if type == "double_coins":
        _apply_reward()

func _apply_reward() -> void:
    coins *= 2
    PlatformBridge.save_data({"coins": coins})
    update_ui()
```

#### 2. Interstitial Ads (Межстраничная Реклама)

**Правила показа:**

- Только между матчами (не во время игры)
- Не чаще 1 раза в 2-3 минуты
- Не показывать если игрок только зашёл

**Реализация:**

```gdscript
# В GameManager.gd
var last_ad_time: int = 0
const AD_COOLDOWN_SECONDS: int = 180  # 3 минуты

func show_interstitial_if_ready() -> void:
    var current_time = Time.get_unix_time_from_system()
    if current_time - last_ad_time >= AD_COOLDOWN_SECONDS:
        PlatformBridge.show_interstitial()
        last_ad_time = current_time

func on_match_ended() -> void:
    # Показываем результаты
    show_match_results()
    
    # Проверяем кулдаун рекламы
    show_interstitial_if_ready()
```

### Graceful Handling (Обработка Ошибок)

```gdscript
func safe_show_ad(ad_type: String) -> void:
    var success = await PlatformBridge.show_rewarded_video(ad_type)
    if not success:
        # Реклама не показала - даём утешительный приз
        give_consolation_reward()
        print("Ad failed, gave consolation reward")
```

---

## 🚀 Развёртывание Сервера

### Вариант 1: Render.com (Бесплатно)

1. Создайте репозиторий на GitHub с папкой `server/`
2. Зарегистрируйтесь на [render.com](https://render.com)
3. Создайте новый сервис типа "Web Service"
4. Подключите GitHub репозиторий
5. Настройки:
   - **Root Directory:** `server`
   - **Build Command:** `npm install && npm run build`
   - **Start Command:** `node dist/server.js`
   - **Environment Variables:**
     - `PORT=2567`
     - `PUBLIC_ADDRESS=your-app.onrender.com`

### Вариант 2: Fly.io

```bash
# Установите flyctl
brew install flyctl

# Инициализируйте приложение
cd server
flyctl launch --name arena-bowl-server

# Настройте Docker (создайте Dockerfile)
cat > Dockerfile << EOF
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .
RUN npm run build
EXPOSE 2567
CMD ["node", "dist/server.js"]
EOF

# Деплой
flyctl deploy
```

### Вариант 3: Hetzner (VPS, ~€5/мес)

```bash
# Подключение к серверу
ssh root@your-server.hetzner.cloud

# Установка Node.js
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt-get install -y nodejs npm

# Клонирование проекта
git clone <your-repo>
cd arena_bowl_game/server

# Установка и запуск
npm install
npm run build

# Создание systemd сервиса
cat > /etc/systemd/system/arena-bowl.service << EOF
[Unit]
Description=Arena Bowl Game Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/arena_bowl_game/server
ExecStart=/usr/bin/node dist/server.js
Restart=always
Environment=NODE_ENV=production
Environment=PORT=2567

[Install]
WantedBy=multi-user.target
EOF

systemctl enable arena-bowl
systemctl start arena-bowl
systemctl status arena-bowl
```

### Настройка Firewall

Откройте порт 2567 для WebSocket подключений:

```bash
# UFW (Ubuntu)
ufw allow 2567/tcp

# iptables
iptables -A INPUT -p tcp --dport 2567 -j ACCEPT
```

---

## 📦 Сборка и Публикация

### Экспорт в HTML5

1. В Godot: `Project → Export → Add... → HTML5`
2. Настройки экспорта:
   - **Debugging:** Выключено для релиза
   - **VRAM Compression:** Выключено (веб)
   - **Customize Template:** Можно добавить кастомный HTML
3. Нажмите `Export Project` → выберите папку `build/web/`

### Оптимизация для Веба

```gdscript
# В project.godot
[application]
config/features=PackedStringArray("4.2", "Forward Plus")

[display]
window/size/viewport_width=1280
window/size/viewport_height=720
window/stretch/mode="canvas_items"  # Быстрее чем 2d

[rendering]
renderer/rendering_method="forward_plus"
quality/shadows/max_distance=50.0
quality/reflections/glow_enabled=true
quality/anti_aliasing/msaa_3d=2  # Баланс качество/производительность

[physics]
3d/default_gravity=15.0  # Чуть выше для ощущения аркадности
```

### Публикация на Платформы

#### Яндекс.Игры

1. Зарегистрируйтесь в [Консоли разработчика](https://games.yandex.ru/console/)
2. Создайте новое приложение
3. Загрузите ZIP-архив с содержимым `build/web/`
4. Заполните метаданные:
   - Название: "Arena Bowl: Автобои"
   - Описание: "Динамичные аркадные бои на машинах..."
   - Категория: "Гонки" / "Экшен"
   - Возрастной рейтинг: 6+
5. Интегрируйте Yandex SDK (см. раздел Platform Bridge)
6. Отправьте на модерацию (1-3 дня)

#### VK Direct Games

1. Откройте [VK Developers](https://dev.vk.com/)
2. Создайте новое приложение типа "Direct Game"
3. Загрузите архив с игрой
4. Укажите URL на HTTPS хостинг (GitHub Pages, Netlify, Vercel)
5. Интегрируйте VK Bridge для сохранений и рекламы
6. Пройдите модерацию

#### Telegram WebApp

1. Создайте бота через [@BotFather](https://t.me/BotFather)
2. Используйте команду `/newapp` для создания Web App
3. Укажите URL на вашу игру
4. Игра будет доступна прямо в Telegram

#### CrazyGames

1. Зарегистрируйтесь на [CrazyGames Developer Portal](https://developer.crazygames.com/)
2. Подайте заявку на публикацию
3. Интегрируйте CrazyGames SDK для рекламы
4. Загрузите билд через их портал

---

## 🗺️ План Развития

### Ближайшие Задачи (Post-Sprint 4)

#### Технические Улучшения

- [ ] **GDExtension для Colyseus:** Native WebSocket клиент для Godot вместо HTTP-fallback
- [ ] **Lag Compensation:** Rewind-механизм для точной валидации попаданий
- [ ] **Anti-Cheat:** Валидация скоростей и телепортов на сервере
- [ ] **Performance Profiling:** Оптимизация draw calls, LOD системы

#### Контент

- [ ] **Новые карты:** 3-5 различных арен с уникальными механиками
- [ ] **Оружие:** 5+ новых типов (ракеты, лазер, дробовик, миномёт)
- [ ] **Машины:** 10+ моделей с разными характеристиками
- [ ] **Скины:** 20+ раскрасок, наклейки, следы от шин

#### Режимы Игры

- [ ] **Захват флага:** Классический CTF с командной игрой
- [ ] **Царь горы:** Удержание зоны для получения очков
- [ ] **Выживание:** Волны ботов с нарастающей сложностью
- [ ] **Футбол:** Режим в стиле Rocket League с мячом

#### Мета-игра

- [ ] **Ежедневные задания:** Система квестов с наградами
- [ ] **Сезоны:** Battle Pass с эксклюзивными предметами
- [ ] **Достижения:** Steam/Yandex/VK achievements
- [ ] **Лидерборды:** Глобальные рейтинги игроков

#### Социальные Функции

- [ ] **Кланы/Гильдии:** Команды игроков с общим чатом
- [ ] **Друзья:** Система друзей с приглашениями в лобби
- [ ] **Реплеи:** Запись и просмотр матчей
- [ ] **Стриминг:** Интеграция с Twitch/YouTube

### Долгосрочная Дорожная Карта

#### Квартал 1 (Q1 2025)

- Релиз ранней версии на Яндекс.Играх
- Сбор фидбека и багфикс
- Добавление 2 новых карт
- Интеграция всех платформ (Яндекс, VK, Telegram)

#### Квартал 2 (Q2 2025)

- Введение сезонной системы
- Турнирный режим с призами
- Мобильная адаптация (сенсорное управление)
- Локализация: EN, RU, TR, ES

#### Квартал 3 (Q3 2025)

- Партнёрская программа для стримеров
- Пользовательские турниры
- Расширенная кастомизация (конструктор машин)
- Кроссплатформенный прогресс

#### Квартал 4 (Q4 2025)

- PvP рейтинг система (MMR)
- Киберспортивные функции
- VR поддержка (экспериментально)
- Порт на мобильные платформы (iOS/Android)

---

## 🐛 Известные Проблемы и Решения

### Проблема 1: Рассинхронизация Физики

**Симптомы:** Игроки видят разные позиции после нескольких секунд игры

**Решение:**
- Увеличьте частоту патчей сервера (`PATCH_RATE = 30`)
- Включите client-side prediction с reconciliation
- Используйте фиксированный timestep для физики

```gdscript
# В project.godot
[physics]
common/physics_ticks_per_second=60
```

### Проблема 2: Долгая Загрузка на Мобильных

**Симптомы:** Загрузка более 10 секунд на 3G

**Решение:**
- Включите gzip/brotli сжатие на сервере
- Разрежьте ресурсы на чанки (lazy loading)
- Используйте texture compression (ETC2/ASTC)
- Предзагружайте только первую сцену

### Проблема 3: Реклама Не Показывается

**Симптомы:** `show_rewarded_video()` не вызывает callback

**Решение:**
- Проверьте что платформа поддерживает рекламу
- Убедитесь что SDK инициализирован
- Добавьте обработку ошибок в JS callback
- Проверьте лимиты показов (frequency capping)

---

## 📞 Поддержка и Сообщество

### Ресурсы

- **Документация Godot:** https://docs.godotengine.org/
- **Colyseus Docs:** https://docs.colyseus.io/
- **Яндекс SDK:** https://yandex.ru/dev/games/doc/ru/
- **VK Bridge:** https://dev.vk.com/bridge/overview

### Контакты

Для вопросов по интеграции и партнёрству:
- Email: developer@arenabowl.game (пример)
- Discord: [ссылка на сервер]
- Telegram канал: @arenabowl_dev

---

## 📄 Лицензия

Проект распространяется под лицензией MIT License.

```
Copyright (c) 2024 Arena Bowl Game Developers

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.
```

---

## 🙏 Благодарности

- **Godot Engine** — мощный open-source движок
- **Colyseus** — отличная библиотека для мультиплеера
- **Сообщество инди-разработчиков** — за вдохновение и поддержку

---

**Удачи в разработке! 🚀🎮**
