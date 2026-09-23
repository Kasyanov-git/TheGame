# Overdrive Arena

**Казуальный vehicular-арена-шутер** (Rocket League × World of Tanks) для веб-платформ:
Яндекс.Игры, VK Direct Games, CrazyGames, Telegram WebApp.

Движок: **Godot 4.x** · Рендер: `gl_compatibility` (WebGL2-совместимый билд) ·
Физика: GodotPhysics3D (raycast-подвеска, не `VehicleBody3D`) ·
Мультиплеер (Sprint 3): Colyseus.js · Бэкенд сохранений (Sprint 4): SDK платформ.

Репозиторий ведётся по спринтам из ТЗ. **Sprint 1 — готов и проверен.**

---

## Sprint 1 — Core Physics (готово)

> Цель спринта: аркадная машинка, «бесшовная» арена-чаша, динамическая камера
> и узлы-заглушки под будущие орудия/неткод.

### Что реализовано

**1. Arcade Vehicle Controller — `src/vehicle/arcade_vehicle.gd`**

* `RigidBody3D` + сферический коллайдер-«юбка» (скольжение по кромкам тримеша)
  + **4 raycast-подвески** — запросы идут напрямую через
  `PhysicsDirectSpaceState3D.intersect_ray` (одинаково на GodotPhysics и Jolt,
  детерминированный порядок на тике, готовые «переехать» на сервер в Sprint 3).
* `max_speed = 45 м/с` (мягкий лимит продольной скорости; боковая составляющая
  заноса не ограничивается), `engine_force = 80 Н` (при `mass = 6 кг` ≈ 13.3 м/с²;
  все силы подвески/прижима нормализованы массой — тюнинг не зависит от массы тела).
* Поворот — велосипедная модель `ω = v/L·tan(δ)`, `steer_limit 35°`
  сужается до ~12° на максимуме; **ось руления — нормаль контакта**, поэтому
  машина рулит «вдоль стены» на банке, а не вокруг мирового Up.
* `drift_grip_factor = 0.35`: боковая скорость гасится экспоненциально
  (`grip_rate`, в заносе ×0.35) — fps-независимо и предсказуемо для неткода.
* `downforce_strength = 15g` на `max_speed` (растёт с квадратом скорости,
  +бонус на бусте) — удержание на изогнутых стенах как в Rocket League:
  вертикальную стену держишь только на высокой скорости.
* Стабилизация в воздухе: мягкий выравнивающий момент pitch/roll к горизонту
  + сохранение yaw; на земле корпус прижимается к нормали контакта
  + анти-ролл. Асимметричный демпфер подвески (отбой ×3) — машина не прыгает
  «на батуте» после жёсткой посадки.
* Буст: `boost_multiplier = 1.7`, энергия с расходом/регенерацией (в заносе
  не копится), `respawn` по R, авто-респавн при падении за арену.
* Готовые развязки: `set_external_input()` — единый вход для ботов и нет-реплея,
  `get_net_state()/apply_net_state()` — скелет авторитарного сервера,
  сигналы `landed()/respawned()`, `get_hardpoint(socket)` для оружия.

**2. Seamless Arena — `src/arena/arena_bowl.gd`**

* Арена генерируется процедурно **из одной функции** (меш и trimesh-коллизия
  идентичны — лучи подвески никогда не «видят» другую геометрию, чем рисует
  рендер).
* План — суперэллипс (скруглённый овал, полуоси 52×36 м); сечение — цепь дуг
  с C1-касательной: пол → радиус скругления 8 м → банк 36° → доворот в
  вертикаль → стена 7 м → **губа-оверхэнг**, нависающая внутрь (за борт
  улететь нельзя). Прямых углов 90° нет (ТЗ: min 3–5 м — у нас 8).
* `Friction = 0.1`, `Restitution = 0.3` — машина скользит вдоль стены,
  теряя минимум импульса.
* Стиль low-poly без текстур: цвет — вершинные краски (материал +
  `vertex_color_use_as_albedo`), двойное лицо (cull disabled), 7.8k треугольников.
* Точки-заглушки `SpawnPoints/` (группа `arena_spawn`) — спавнер матча Sprint 3.

**3. Dynamic Camera — `src/camera/chase_camera.gd` + `camera_rig.tscn`**

* `SpringArm3D` (плечо 6.0 м, наклон −15°) + `Camera3D`; ретракт при окклюзии
  ареной встроен (SpringArm сам кидает луч по маске слоя Arena).
* Всё сглаживание в `_process()` по **интерполированному** (`physics_interpolate`)
  transform машины → нет дерганья физического шага (DoD 3).
* Коэффициент 0.12/кадр пересчитан через `1−(1−k)^(dt·60)` — одинаковое
  ощущение на 60/120/144 Гц.
* Динамический FOV 75°→90° (скорость/буст/дрифт), плечо удлиняется со
  скоростью, heading = смесь курса и вектора скорости (камера «заглядывает»
  в занос), look-ahead по направлению движения.

**4. Definition of Done**

| # | Критерий | Статус |
|---|-----------|--------|
| 1 | Отзывчивый разгон/торможение/аркадный дрифт | ✅ проверено смоук-тестом: 0→~34 м/с за 1.5 с, боковое скольжение в заносе, буст выше базового лимита (cap ×1.7 соблюдён) |
| 2 | Закруглённые стены: без хаотичных переворотов и «влипания» | ✅ профиль C1, тримеш без вырожденных треугольников (дедуп стыков), `backface_collision` + невидимый «потолок» страховкой |
| 3 | Плавная камера без дёрганья physical step | ✅ `_process` + physics-interpolation + framerate-независимый lerp |
| 4 | Spawn Points / Hardpoints заглушки | ✅ `Arena/SpawnPoints` (4 шт, группа `arena_spawn`), `PlayerCar/Hardpoints` (WeaponSocket_L/R/C, BoostFX_Rear), сокет-API `get_hardpoint()`, net-stubs |

### Как проверено

13-шаговый смоук-тест (`tests/smoke_driver.gd`) прогнан **на реальном движке
Godot 4.7 headless** (wasm-сборка через Node, см. ниже): ускорение, лимиты
скорости, руление, занос, буст-энергия, спавн/респавн, генерация коллизии
арены (7808 trimesh) — `SMOKE: PASS (0 fails)`.

### Как запустить

**В редакторе (основной путь):** Godot **4.3+** → «Project Manager» → Import
`project.godot` → **F5**. Управление: `WASD/стрелки`, `Space` — буст,
`Shift` — дрифт, `R` — сброс.

**Headless-CI (без GPU и редактора):**

```bash
./tools/headless/run_smoke.sh
```

Ставит из npm wasm-рантайм Godot, «затащивает» проект в эмулируемый
файл-систему FS, крутит smoke-сцену и возвращает 0 при `SMOKE: PASS`.
Нюанс: у web-рантайма нет редакторского import-кэша, поэтому скрипт
на лету снимает copy-аннотации пользовательских классов (`class_name`-типы);
код в репозитории остаётся полностью типизированным.

### Структура

```
project.godot            — настройки: input map, слои, gl_compatibility, 60Hz
icon.svg
src/
  main/main.(gd|tscn)    — сборка сцены + спавнер (использует SpawnPoints)
  arena/arena_bowl.(gd|tscn)   — процедурная чаша: меш+коллизия+физматериал
  vehicle/arcade_vehicle.gd     — контроллер машины (весь тюнинг — @export)
  vehicle/player_car.tscn       — тело: box+sphere коллайдеры,Susp-анкеры,
                                  Visual (шасси/кабина/колёса), Hardpoints
  camera/chase_camera.gd        — риг: SpringArm3D + Camera3D
  camera/camera_rig.tscn
  ui/debug_hud.(gd|tscn)        — скорость/буст/контакт/FPS
tests/
  smoke_driver.gd, smoke.tscn   — 13 проверок физики (см. выше)
  run_smoke.sh-обёртка -> tools/headless/run_smoke.sh
tools/headless/
  godot-wasm-runner.mjs         — Node-runner wasm-движка (browser-shims,
                                  frame-pump через GodotInstance.iteration)
  run_smoke.sh                  — вся подготовка (npm, staging, type-strip)
docs/sprint1_report.md          — отчёт по спринту
```

### Ключевые параметры (все — `@export`, правятся в инспекторе)

| Параметр | Значение | Где |
|---|---|---|
| max_speed / boost ×1.7 | 45 м/с / 76.5 м/с | `arcade_vehicle.gd` |
| engine_force / brake | 80 / 120 Н @ mass 6 кг | там же |
| steer_limit / high-speed keep | 35° → 35% | там же |
| grip_rate / drift factor | 9.0 / 0.35 1/с | там же |
| downforce | 15g @ max_speed | там же |
| suspension | rest 0.55 м, travel 0.28 м, k 140 g/м, c 16 (отбой ×3), cap 14g | там же |
| arena | 52×36 м, fillet 8, bank 36°, wall 7 м, lip 26° | `arena_bowl.gd` |
| физматериал | friction 0.1, restitution 0.3 | `arena_bowl.gd` |
| camera | arm 6 м, pitch −15°, smooth 0.12, FOV 75→90 | `chase_camera.gd` |

### Технические решения, зафиксированные на Sprint 1

* **Не `VehicleBody3D`** — вместо него velocity-space-контроллер: отзывчивость,
  независимость от mass/гравитации, детерминизм (критично для
  client-prediction в Sprint 3).
* **Trimesh-коллизия арены** из той же генерации, что и меш; `backface_collision`
  включает двусторонность (губа-оверхэнг работает снаружи). При смене плана
  карты достаточно заменить `_plan_point()`.
* **GodotPhysics3D** закреплён в `project.godot` явно: web-экспорт не возит
  Jolt-модуль, а нам нужен один и тот же результат в браузере и на сервере.
  (На dev-машинах с GodotPhysics поведение совпадает с проверенным.)
* **Сцена без ассетов** — процедурка + примитив-меши: быстрый web-бандл,
  никакой текстурной пайплайн-зависимости до арта Sprint 4.

### Дальше (по ТЗ)

* **Sprint 2 — Combat & Perks**: снаряды по `WeaponSocket_*`, HP-валидация,
  подбираемые плюшки (`add_boost()` уже ждёт буст-пады; `landed()/respawned()`
  — крючки эффектов).
* **Sprint 3 — Networking & Bots**: Colyseus-комната (state = `get_net_state()`),
  боты = `set_external_input()` + FSM, заполнение слотов через 5–7 с.
* **Sprint 4 — UI, Meta & SDK**: Platform Wrapper (Яндекс/ВК/Crazy/Telegram),
  гараж на тех же hardpoints, rewarded-реклама, лидерборды.
