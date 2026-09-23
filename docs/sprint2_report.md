# Отчёт Sprint 2 — Combat & Perks

## Итог

MVP Sprint 2 реализован и **проверен живым прогоном на движке** (Godot 4.7.2
wasm-headless, `./tools/headless/run_smoke.sh`): **`SMOKE: PASS (0 fails)` —
52 проверок** (13 из Sprint 1 + 39 новых боевых). Все 4 пункта DoD ТЗ
покрыты автотестом (см. «Проверки» ниже).

## Что реализовано (по пунктам ТЗ)

### 1. Hardpoints и турельный монтаж

* Сокеты на машине: `GunMountPoint` (крыша), `WeaponSocket_L/R` (крылья) —
  `src/vehicle/player_car.tscn`, узел `Hardpoints`.
* `ArcadeVehicle::mount_weapon(weapon, socket)` — оружие становится **дочерним
  узлом сокета** (трансформ наследуется — крылья/кузов «носят» ствол), сигнал
  `weapon_mounted` для HUD/неткода.
* `src/combat/turret_aimer.gd` — наведение: **camera ray из центра экрана** в
  3D-мир (`project_ray_normal` → `intersect_ray`), два пивота (yaw/pitch),
  скорость поворота ограничена `turret_rotation_speed = 12.0 рад/с` —
  наведение не мгновенное; питч зажёрстан **−10°…+30°**. «Aim-assist»: если
  рядом с точкой луча (< `snap_radius`) есть чужой хитбокс (слой Hitboxes),
  прицел цепляет его — стандарт казуальных шутеров.

### 2. BaseWeapon (`src/combat/base_weapon.gd`)

* Параметры ТЗ: `fire_rate = 0.15 с`, `damage = 15`, `energy_cost = 6`
  (ресурс `BOOST_ENERGY` — выстрел тратит буст) / `ammo_max = 80 +
  ammo_regen` (ресурс `AMMO`), `spread_degrees = 1.5` (равномерный конус).
* **Arcade Fast Projectile** (пушка, основная): `Area3D`-снаряд
  (`projectile.gd/.tscn`), `speed = 120 м/с`, oversized-триггер
  `r = 0.9 м`, `lifetime = 3.0 с`, деактивация на первом касании (геометрия /
  чужая машина). Полёт — перемещением узла + **sweep-ray prev→cur** на тик
  (в `move_and_slide` не нужен; не «тоннельит» сквозь стены на 120 м/с).
* **Hitscan** (пулемёт): мгновенный `intersect_ray` от дула на 160 м,
  `fire_rate = 0.07`, `damage = 6`, разброс 2.4°; трассер-плейсхолдер на кадр.

### 3. HealthComponent (`src/combat/health_component.gd`)

* `max_health = 100`, `current_health`, `is_dead`;
  `take_damage(amount, attacker_id)` → false, если мертва/под щитом.
* Смерть: `on_vehicle_destroyed(vehicle, attacker_id)`, физика выключается
  (freeze + kinematic, коллизии скрыты), ввод блокируется (`is_respawning()`),
  Visual скрывается, **explosion placeholder** со **ForcePush** по соседним
  машинам (импульс, затухающий с расстоянием).
* `respawn_delay = 4.0 с` → респавн в `arena.get_random_spawn_point()`
  (тот же генератор, что и старт матча), HP/щит/слои восстановлены.

### 4. Pickups (`src/combat/pickup_base.gd`)

* `Area3D`-триггер (слой Pickups=16), крутящаяся 3D-иконка,
  `cooldown = 10.0 с` (фигура гаснет на кулдауне — видно «зарядку»).
* Типы: **Nitro** (+100 % буста = `add_boost(capacity)`), **Repair**
  (+35 HP), **Shield** (поглощает урон 6 с, HUD-индикатор).
* На карте 5 точек (main.tscn): нитро север/юг, ремонт запад/восток,
  щит в центре — классическое распределение «рискованных» бонусов.

### 5. Сигналы VFX/AUI (крючки, а не рендер)

`health_changed(new_hp, max_hp)` · `hit_registered(target_position, damage,
is_kill)` · `weapon_fired(muzzle_position, direction)` — вешаются на HUD,
звук и будущие партиклы; `DebugHud` уже показывает HP-бар, всплашку хита,
прицел-крест, SHIELD/DESTROYED.

## DoD — чем подтверждается (smoke)

| Пункт DoD | Проверки в логе |
| --- | --- |
| Машина наводится в точку camera-ray и стреляет с указанным rate | `cannon cadence fire_rate=0.15s (4 shots/30 тик.)`, `shot interval ~9 ticks`, `turret converged on crosshair target (err 0.05°)`, `turret speed cap <= 12 rad/s (max step 0.2000 rad)`, `barrel pitch within [-10..+30]`, `shot direction follows barrel` |
| Снаряды наносят урон, деактивация о стену/игрока | `projectiles damaged enemy (3 hits)`, `enemy hp reduced exactly by damage*hits`, `all projectiles despawned after impact`, `projectile despawns on wall hit`, `projectile despawns on lifetime expiry` |
| HP≤0 → взрыв/скрытие/блокировка ввода → респавн через 4 с в случайной точке | `enemy marked dead`, `vehicle physics disabled/hidden`, `input blocked while respawning`, `explosion placeholder spawned`, `enemy revived after respawn_delay`, `respawned on a spawn point (dist 1.5)` |
| Pickups применяют эффект и уходят в кулдаун | `repair heals +35`, `cooldown blocks re-pickup`, `nitro refills boost to 100%`, `shield grants ~6s`, `shield absorbs damage`, `shield expires` |

## Баги, найденные только живым прогоном (ценность валидации)

1. **`Basis.xform()` удалён в Godot 4.7** (deprecated с 4.4). В wasm-рантайме
   вызов несуществующего метода из Variant-цепочки **не печатает ошибку и
   молча обрывает функцию** — турель «не крутилась» без единого скрипт-эррора.
   Фикс: `inv.basis * vec`. Поймано только поведением, не логом.
2. **Headless-viewport имеет высоту 0** (`get_visible_rect().size == (1280, 0)`)
   → `project_ray_*` возвращает вырожденный результат + ошибки
   `Projection::get_endpoints`, а вырожденный `intersect_ray` (from==to)
   роняет Jolt-билдер выпуклой оболочки (`cast_motion`) — 968 строк спама и
   мусорная точка прицела. Фолбэк в `turret_aimer` (и зеркало в смоке): при
   `dir.length_squared() < 1e-6` — цель «курсом машины» в 24 м. В браузере
   ветка недостижима.
3. **`global_position` нельзя присваивать узлу вне дерева** — Godot 4 ругает
   `!is_inside_tree()` и молча игнорирует запись; impact/explosion
   плейсхолдеры спавнились в нуле. Фикс: `fx.position = at` до `add_child`
   (хост — узел мира в нуле) либо сет после добавления.
4. **wasm-сборка не резолвит `class_name`-идентификаторы в рантайм-коде**
   (`TurretAimer.new()` падает; аннотации `: Type` безопасно стрипаются
   sed'ем, а вызовы — нет). Паттерн проекта: `const _SCRIPT := preload(...)`,
   `_SCRIPT.new()`.
5. **Слой-биты ≠ номера слоёв**: Hitboxes = 8 (bit 4), Pickups = 16 — в
   первой версии masks были 4/5. Чинится только таблицей в `project.godot`
   + константами в скриптах.

## Что специально НЕ сделано в Sprint 2

* **Net-применение** состояния оружия: `apply_net_state()` принимает keys,
  но интерполяцию чужих турелей/снарядов делает Sprint 3 (там же —
  авторизация урона на сервере; сейчас `register_projectile_hit` — доверчивый).
* Арт/партиклы/звук: только плейсхолдеры-мэши (взрыв — эмиссивная сфера +
  кольцо, impact — вспышка, трассер — цилиндр); сигналы для них — готовые.
* Бонус-предметы на сети (детерминированный таймер спавна — Sprint 3),
  destructibles-объекты карты (HealthComponent к ним прикручивается за строку).
* Ретраггер-щита, дробовики/заряженные выстрелы — вне ТЗ.

## Ключевые параметры (все — `@export`)

| Параметр | Значение | Где |
| --- | --- | --- |
| turret_rotation_speed | 12.0 рад/с | `base_weapon.gd` → `turret_aimer.gd` |
| pitch clamp | −10°…+30° | `turret_aimer.gd` |
| aim snap radius | 12 м | `turret_aimer.gd` |
| fire_rate / damage / energy | 0.15 с / 15 / 6 | `weapon_cannon.tscn` |
| projectile speed / lifetime | 120 м/с / 3.0 с | `projectile.gd` |
| trigger radius | 0.9 м | `projectile.tscn` |
| MG | 0.07 с, 6 dmg, 1.5°…2.4°, 80+реген | `weapon_mg.tscn` |
| max_health / respawn_delay | 100 / 4.0 с | `health_component.gd` |
| explosion push | r 7.5 м, импульс 11 | `explosion_placeholder.gd` |
| pickup cooldown | 10.0 с | `pickup_base.gd` |
| Nitro / Repair / Shield | +100 % / +35 HP / 6 с | `pickup_base.gd` enum |
