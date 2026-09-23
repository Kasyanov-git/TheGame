# Sprint 3 — Сетевой слой (Colyseus-сервер + netcode + боты + клиенты)

Ветки: `arena/01a0ab4e-thegame` → PR #3. Стек: Node.js + TypeScript,
`@colyseus/core@0.18` + `@colyseus/ws-transport` (без платных зависимостей),
`@colyseus/schema@5`; клиенты — Godot 4 (WebSocket relay) и браузер (Three.js,
`@colyseus/sdk`).

## Что сделано

### 1. Игровой сервер (`server/`)
- **BattleRoom** — `maxClients=4`, `patchRate=50 мс` (20 Гц снапшоты),
  matchmaking-таймаут 5 с → пустые слоты заполняются `ServerBotController`
  (DoD «соло → 3 бота через 5 с» — подтверждено тестом).
- **schema.ts** — `PlayerState {x,y,z,rotX/Y/Z,vx,vy,vz,hp,score,isBot,
  weaponType,+shieldT,boostT,aimYaw,aimPitch}` (расширение зафиксировано ниже),
  `BattleState {MapSchema players, MapSchema projectiles, gameTimer,
  matchState WAITING/PLAYING/FINISHED, winnerId}`, `PickupState {type,x,z,cd}`.
  Все поля с `.default()` — delta-кодинг не гоняет пустые инициализаторы.
- **sim.ts** — серверная физика = зеркало Godot-модели (ACCEL 13.3, cap 45 м/с,
  нитро ×1.5, велосипедный руль, кламп турели 12 рад/с, снаряды 120 м/с,
  hitscan, хит-сферы 2.2 м, эллипс-арена). Матч: FFA 120 с, frags → score,
  FINISHED → авто-dispose комнаты.
- `npm run start` — баннер + `GET /health` + WS на :2567 (DoD a).

### 2. Netcode (ТЗ п.2)
- **UserCommand 30 Гц**: `throttle, steer, drift, boost, fire, aimYaw,
  aimPitch, seq` + **самоотчёт предсказания** `rx,ry,rz,rvx,rvz`.
- **Client-side prediction**: локальная физика крутится у клиента сразу;
  сервер принимает его позицию (trust-but-validate), а не пересчитывает байт-в-байт.
  Валидация репорта: скорость меряется **между последовательными принятыми
  репортами** (`|Δ| ≤ SPEED_CAP·Δt + 3 м`) + границы арены. Серверная
  dead-reckoning-интеграция — только сглаживание/резерв, не якорь (иначе любой
  серверный телепорт — респавн, админ-команда — ломал клиенту синхрон).
  Репорт-отвергнут → `reconcile` с серверной поз → клиент делает мягкий
  rubber-band при расхождении >4 м. `trust` (0..1) деградирует при откатах —
  читерство телепортом режется сразу (тест: ×20 телепорт-репорт → trust 0,
  позиция не улетела).
- **Интерполяция чужих**: буфер 100 мс (`INTERP_DELAY`), lerp позиции +
  slerp/свёрнутый lerp yaw — в Godot (`net_avatar.gd`) и web-demo.
- **Hit validation авторитарна на сервере**: `allowRewindState` — сервер держит
  историю (`lastSeenBy` рендер-тайминга отправителя) и проверяет выстрел по
  лаг-компенсированной позиции цели; урон/смерть/респавн только сервером,
  hp реплицируется схемой + события `ev` (fire/hit/kill/death/spawn/pickup/
  start/finished) для ВЖХ.
- **Симулирование задержки** `POST /debug/latency {ms}` — RTT режется в обе
  стороны; смоук гоняет hitscan по убегающей цели при 300 мс RTT (попадание
  засчитано, репорты приняты, trust 1.0).

### 3. Боты (`bots.ts`, ТЗ п.3) — конечный автомат на сервере
- `WANDER` — случайные точки, сброс газа у стен (эллипс SAFE-зоны);
- `SEEK_PICKUP` — ближайшая аптечка/нитро, если hp<40% или буст кончился
  (тест: бот дошёл до рем-пикапа, сервер применил +35);
- `COMBAT` — цель ≤45 м;стрельба с lead-prediction от скорости цели; турель 12 рад/с
  + `aim_error ±3°`; огонь при |ошибка|<5°; скорострельность лимит сервера
  одинаков для людей и ботов (8 выстр./с MG — тест).
- `disconnectBot()` — при входе реального игрока в комнату с ботами один бот
  выгружается и заменяется игроком (тест: 3 бота → вход → 2 бота+игрок).
- Память агрессии: кто ударил (`lastHitBy`) — держит стрелка, а не переключается
  на ближайшего (исправлено: nearest-скан не перетирает удерживаемую цель).

### 4. Клиенты (ТЗ п.4)
- **Godot 4** (`src/net/`): autoload **NetworkManager** — сигналы `onJoin /
  onLeave / onStateChange / onPlayerAdd / onPlayerRemove` ровно по ТЗ; вход
  флагом `--net[=ws://host:2567/godot-relay]` (web-экспорт — тот же URL).
  Шлёт UserCommand 30 Гц, читает snapshot, спавнит `NetAvatar` (marionетка
  player_car.tscn: freeze, collision off, `control_enabled=false`),
  интерполирует 100 мс, hp/щит реплицирует в `HealthComponent`
  (`set_net_hp/set_net_shield`, в net-режиме локальный `take_damage` игнорируется),
  Pickups переходят в визуальный режим (`set_net_cd` из снапшота), чужие
  выстрелы — декоративные снаряды (source=null, урона не наносят).
  `WebSocketPeer` создаётся через `ClassDB` — в сборках без WS-модуля (wasm
  headless) синглтон деградирует в offline и остаётся тестируемым.
  **Godot-соло не сломан**: без `--net` игра идёт офлайн (все 52 прошлых
  проверки S1+S2 зелёные; всего в смоуке 68).
- **web-demo/** (`index.html`) — Three.js + `@colyseus/sdk`: два окна браузера
  синхронизируют движение и стрельбу (DoD b вручную; автоматизированный
  эквивалент — смоук на двух SDK-клиентах). Матчмейкинг-кнопка, тапы пикапов,
  таблица фрагов, hp-бар, rubber-band. Работает на e2b-preview (URL-хост с
  портом переписывается на :2567) и на `localhost`.
- **Godot relay** (`server/src/relay.ts`) — сервер принимает ещё и «чистый»
  WebSocket `/godot-relay` (JSON: `in/st/ev/rec`) и сам подключает Godot-клиента
  к BattleRoom полноценным SDK-игроком: один и тот же авторитарный сервер для
  web и Godot-сборок, без дублирования логики. Смоук проверяет полный цикл
  relay-клиента (snapshot, drive без телепортов, события выстрела/попадания).

## Отступления от ТЗ (осознанные, документируем)
1. `PlayerState` дополнен `shieldT/boostT/aimYaw/aimPitch` — без них клиент не
   отрисовал бы щит/нитро/турель; `PickupState`-мапа добавлена (5 точек
   захвата — состояние кулдаунов реплицируется вместо «локальной симуляции»
   пикапов на клиенте).
2. Boost-энергия (бесконечная шкала Godot-клиента) в сетевом режиме
   управляется пикапами Nitro (как на сервере); «своя» шкала boost-кнопки —
   Sprint 4 (баланс аркады), поле `boost` в UserCommand уже передаётся.
3. Проверка Movement-репортов принята trust-but-validate, а не full-replay:
   сервер физика тот же по константам, но не бит-в-бит Godot-raycast. Для
   дешёвой аркады это стандартный компромисс (значения-clamp + anti-teleport
   закрывают 99% читов; серверный fallback интеграции доверена ботам).
4. Таймеры матча — на `room.clock` (colyseus/timer не подключали; в 0.18 у
   returned handle — `.clear()` вместо `clearTimeout` — учтено).

## Как проверено (регрессия)
- `server/` : `npm run build && npm test` → **SMOKE3: 24/24**, стабильно 5
  прогонов подряд. Сценарии: DoD a–d, предсказание (дрейф клиент↔сервер
  0.00 м), анти-чит (телепорт-спам → reject + trust↓; без серверных телепортов
  max шаг 1.26 м), rate-limit, урон по 15 квантами, события, килл + score +
  респаун 4 с, бот-FSM (SEEK_PICKUP + ремонт + агрессия), hitscan под 300 мс
  RTT (лаг-компенсация попадание + trust 1.0), Godot relay.
  Смоук сам поднимает сервер (`node dist/index.js`); управление сценариями —
  debug-endpoint'ы `/debug/*` (latency/teleport/heal/hurt/pausebot/resetpickups).
  ⚠ В прод-билде их нужно закрыть токеном — записано в ограничения.
- `tests/` Godot: `./tools/headless/run_smoke.sh` → **SMOKE: PASS (68 проверок)**:
  +16 net-юнитов (UserCommand-упаковка, lerpf_angle через ±π,
  интерполяция аватара «ключ→ключ», hp/щит-репликация, net_mode-блокировка
  локального урона, rubber-band >4 м / игнор <4 м, onPlayerAdd/Remove,
  безопасный `join()` без WS-модуля).

## Известные ограничения (принято для спринта)
- 20 Гц снапшоты + 30 Гц инпут: на RTT >~350 мс попадания ощущаются «на честном
  слове» (hitscan компенсирован, снаряду не хватает пере-упреждения) — лечится
  patchRate 30 Гц на платном тарифе хостинга (Render 250 ms → 50 ms).
- Web-demo не шлёт `aimPitch` с учётом рельефа (плоская арена — ок).
- Debug-endpoint'ы `/debug/*` не авторизованы — закрыть токеном перед публичным
  деплоем (Sprint 4, «гигиена прода»).
- Респаун: выбор из 4 фиксированных спавн-пойнтов без проверки «не у дула» —
  спавн-протекцию сделаем в Sprint 4.

## Структура (новые файлы)
```
server/package.json tsconfig.json
server/src/arena.ts schema.ts sim.ts bots.ts BattleRoom.ts relay.ts index.ts
server/test/smoke.mjs            # 24 проверки, сам поднимает сервер
web-demo/index.html              # двухоконный браузерный клиент
src/net/network_manager.gd       # autoload-синглтон (ТЗ п.4)
src/net/net_avatar.gd            # интерполяция чужих (100 мс)
```

## Следующий спринт (по ТЗ)
Sprint 4 — меткий баланс аркады + UI-оболочка платформы: SDK Yandex
(leaderboards/ads заглушки), auth-токен для /debug, спавн-протекция, шкала
boost-энергии серверная, звук-визуал попаданий, экспорт web-билда и
настройка Render/Hetzner deploy (бесплатный tier → бюджетный VPS).
