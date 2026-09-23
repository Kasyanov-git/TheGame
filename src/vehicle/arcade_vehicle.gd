class_name ArcadeVehicle
extends RigidBody3D
## Аркадный контроллер машины (Sprint 1, Core Physics).
##
## Физическая база (по ТЗ, VehicleBody3D НЕ используется):
##   * RigidBody3D + сферический коллайдер «юбки» (скольжение по кромкам
##     тримеша без зацепов) + 4 RayCast-подвески:
##       - определяют grounded / нормаль контакта / компрессию;
##       - пружинят корпус (силы нормализованы через `mass` — тюнинг не
##         зависит от массы тела);
##       - на стене нормаль = нормаль стены -> машина «в присоске» едет
##         по банку как в Rocket League.
##   * Тяга — силы вдоль `-basis.z`, лимит линейной скорости, буст x1.7,
##     занос через ослабление гашения боковой скорости (drift_grip_factor).
##   * Поворот — целевая угловая скорость велосипедной модели
##     ω = v/L · tan(δ), ось вращения — нормаль контакта (руление вдоль
##     стены), ограничена сверху max_yaw_rate.
##   * Air control — мягкий выравнивающий момент pitch/roll + слабый рулёж.
##
## Тюнинг-карта (значения по умолчанию = ТЗ):
##   max_speed 45 м/с | engine_force 80 Н при mass 6 кг ≈ 13.3 м/с²
##   (разгон до потолка ~4 c — плотный аркадный отклик) | steer_limit 35°,
##   сужается до ~12° на максимуме | boost_multiplier 1.7 |
##   drift_grip_factor 0.35 | downforce 15g на max_speed.
##
## Готовность к Sprint 2/3 (узлы и развязки):
##   * $Hardpoints/* — сокеты орудий/тюнинга (оружие Спринта 2 монтируется тут);
##   * set_external_input() — единый вход для ботов (FSM, Sprint 3) и
##     netcode-симуляции; Input читается только когда control_enabled=true;
##   * get_net_state()/apply_net_state() — скелет авторитарной репликации
##     (Colyseus: сервер валидирует попадания/HP, клиент — предсказание);
##   * сигналы landed()/respawned() — точки прицепки SFX/VFX/статистики.

signal landed(impact_speed: float)
signal respawned
signal killed(attacker_id: String)             ## Sprint 2: хук реплеев/статов
signal weapon_mounted(weapon: Node)           ## Sprint 2: HUD/вешалка оружия

const ARENA_LAYER := 1
const _G := 9.80665
const _WHEEL_R := 0.42

# ─────────────────────────── Тюнинг (экспорты) ───────────────────────────
@export_group("Engine")
@export var max_speed := 45.0              ## м/с, лимит продольной скорости (ТЗ)
@export var engine_force := 80.0           ## Н (ТЗ); a = F/m
@export var brake_force := 120.0           ## Н
@export var reverse_max_speed := 12.0      ## м/с назад
@export var coast_drag := 1.0              ## 1/с — инерционный накат без газа

@export_group("Steering")
@export var steer_limit_deg := 35.0        ## ТЗ: 35° на малой скорости
@export var steer_high_speed_keep := 0.35  ## доля лимита на max_speed
@export var max_yaw_rate := 2.9            ## рад/с — потолок разворота
@export var wheelbase := 2.7               ## м, велосипедная модель
@export var turn_response := 15.0          ## 1/с — выход на целевой yaw
@export var steer_input_rate := 4.2        ## сглаживание прокачки руля
@export var steer_return_rate := 6.5       ## возврат руля в центр

@export_group("Grip / Drift")
@export var grip_rate := 9.0               ## 1/с — гашение боковой скорости на асфальте
@export var drift_grip_factor := 0.35      ## ТЗ: grip × 0.35 в заносе
@export var drift_steering_bonus := 1.3    ## в заносе рулим острее
@export var drift_yaw_bonus := 1.15        ## доворот на входе в занос
@export var drift_speed_leak := 0.35       ## занос слегка «съедает» скорость (RL)

@export_group("Downforce")
@export var downforce_strength := 15.0     ## «g» прижима на max_speed (ТЗ: растёт со скоростью)
@export var downforce_min_hold := 0.02     ## микро-прижим на месте (подавляет подпрыгивание)
@export var downforce_boost_bonus := 0.3   ## надбавка на бусте — заезжать на стены со старта

@export_group("Suspension")
@export var susp_rest_length := 0.55       ## м, точка крепления -> земля в покое
@export var susp_travel := 0.28            ## м, рабочий ход
@export var susp_ray_length := 1.6         ## м, длина щупа
@export var susp_stiffness := 140.0         ## «g» на метр сжатия
@export var susp_damping := 16.0
@export var susp_rebound_damp_mult := 3.0   ## ×отбой: гасим rebound, не даём подпрыгнуть           ## 1/с
@export var susp_pull_on_dangle := 0.25    ## подтягивание корпуса к грани на провисе
@export var susp_max_g := 14.0          ## потолок силы пружины в g (анти-взрыв при жёсткой посадке)

@export_group("Air Control")
@export var air_align_speed := 2.4         ## «жёсткость» выравнивания pitch/roll
@export var air_align_deadzone_deg := 12.0 ## мелкие крены не трогаем (не «пластит» прыжок)
@export var air_yaw_deg_per_s := 70.0      ## рулёж в воздухе
@export var air_stab_response := 3.2       ## 1/с мягкость
@export var contact_align_response := 7.0  ## 1/с прижим корпуса к нормали контакта
@export var anti_roll_rate := 2.0          ## 1/с — гасим болтанку крена на стене

@export_group("Boost")
@export var boost_multiplier := 1.7        ## ТЗ: ×1.7 к max_speed
@export var boost_force_mult := 2.6        ## ×engine_force при бусте
@export var boost_capacity := 100.0
@export var boost_drain := 32.0            ## ед/с
@export var boost_regen := 9.0             ## ед/с (только на земле, не в заносе)
@export var boost_pads_refill := 35.0      ## задел Sprint 2: подбор буст-падов

@export_group("Safety")
@export var fall_limit_y := -30.0          ## улетел за арену — автоспавн

# ─────────────────────────── Публичное состояние ───────────────────────────
var grounded := false
var ground_normal := Vector3.UP
var is_drifting := false
var is_on_wall := false
var boost_active := false
var speed_kmh := 0.0
var boost_ratio := 1.0                     ## 0..1 (HUD)
@export var unit_id := ""                  ## сетевой id (дефолт = имя ноды)
var is_dead_emitted := false               ## защита от двойного killed()

# ─────────────────────────── Внутреннее состояние ───────────────────────────
var _steer := 0.0                          ## сглаженный ввод руля -1..1
var _boost_energy := boost_capacity
var _air_time := 0.0
var _wheel_spin := 0.0
var _rays: Array[RayCast3D] = []
var _susp: Array = []                      ## per-wheel {mount, hit, dist, comp, normal}
var _hardpoints: Node3D = null
var _health = null                         ## HealthComponent (узел "Health"), Variant — класс не импортируется
var _weapons: Array = []                   ## BaseWeapon'ы на сокетах
var _respawning := false                   ## пауза управления до респавна
var _wheels_vis: Array[Node3D] = []
var _wheel_yaws: Array[Node3D] = []
var _max_comp := -10.0                     ## макс. компрессия за кадр (grounded-gate)

## ── Заглушки под ботов (Sprint 3) и сетевой ввод ──
@export var control_enabled := true        ## false => машина слушает external/net input
var _ext_input := Vector4.ZERO             ## x=steer, y=throttle, z=boost, w=drift
var _ext_active := false


func _ready() -> void:
	add_to_group("vehicles")
	_collect_children()
	if unit_id == "":
		unit_id = String(name)
	_health = get_node_or_null("Health")
	if _health != null:
		_health.connect("on_vehicle_destroyed", _on_destroyed)
		_health.connect("revived", _on_revived)


# ════════════════════════ Sprint 2: смерть / респавн ════════════════════════

func _on_destroyed(_vehicle: Node, attacker_id: String) -> void:
	_respawning = true
	is_dead_emitted = true
	killed.emit(attacker_id)


func _on_revived() -> void:
	is_dead_emitted = false


func is_dead() -> bool:
	return _health != null and _health.is_dead


## Смерть уже случилась, респавн ещё нет (ввод заблокирован, тело скрыто).
func is_respawning() -> bool:
	return _respawning


## Рандомная точка арены (ТЗ DoD 3: «респавнится на случайной точке спавна»).
func respawn_random() -> void:
	var spawn: Node3D = null
	var arena = get_tree().get_first_node_in_group("arena_bowl")
	if arena != null and arena.has_method("get_random_spawn_point"):
		spawn = arena.get_random_spawn_point()
	else:
		spawn = _nearest_spawn()
	respawn(spawn)


func _collect_children() -> void:
	_rays.clear()
	var susp := get_node_or_null("Susp")
	if susp:
		for c in susp.get_children():
			if c is RayCast3D:
				# сам луч-запрос делает _step_suspension через direct_space_state;
				# нода здесь = якорь позиции + отладочная визуализация в редакторе
				var ray := c as RayCast3D
				ray.cast_to = Vector3(0.0, -susp_ray_length, 0.0)
				ray.enabled = false
				_rays.append(ray)
	if _rays.size() != 4:
		push_warning("ArcadeVehicle: %d лучей подвески (ожидалось 4)" % _rays.size())
	_hardpoints = get_node_or_null("Hardpoints") as Node3D
	_wheels_vis.clear()
	_wheel_yaws.clear()
	for wn in ["WheelFL", "WheelFR", "WheelRL", "WheelRR"]:
		var w := get_node_or_null("Visual/" + wn) as Node3D
		if w:
			_wheels_vis.append(w)
			_wheel_yaws.append(w.get_node_or_null("Steer") as Node3D)


## Внешний вход (боты Sprint 3 / симуляция нет-инпутов).
func set_external_input(steer: float, throttle: float, boost: bool, drift: bool) -> void:
	_ext_input = Vector4(steer, throttle, float(boost), float(drift))
	_ext_active = true


func clear_external_input() -> void:
	_ext_active = false


func _read_input() -> Vector4:
	if _ext_active:
		return _ext_input
	if control_enabled:
		return Vector4(
			Input.get_axis("steer_left", "steer_right"),
			Input.get_axis("brake", "throttle"),
			float(Input.is_action_pressed("boost")),
			float(Input.is_action_pressed("drift")),
		)
	return Vector4.ZERO


func _physics_process(delta: float) -> void:
	if _respawning or is_dead():
		# Sprint 2: смерть/респавн — ввод и движение заморожены (ТЗ DoD 3:
		# «скрывается/блокирует ввод»). HP/таймер живут в HealthComponent.
		return
	var inp := _read_input()
	var steer_in := inp.x
	var throttle := clampf(inp.y, -1.0, 1.0)
	var want_boost := inp.z > 0.5
	var want_drift := inp.w > 0.5

	if control_enabled and not _ext_active and Input.is_action_just_pressed("respawn"):
		respawn()
		return

	# оценка «скорости закрытия» для сигнала приземления (до шага физики)
	var impact_est := maxf(0.0, -linear_velocity.dot(ground_normal))

	var was_grounded := grounded
	_step_suspension(delta)
	if grounded and not was_grounded and _air_time > 0.05:
		landed.emit(impact_est)

	var fwd := -global_transform.basis.z
	var right := global_transform.basis.x
	var up := global_transform.basis.y
	var v_long := linear_velocity.dot(fwd)
	var speed := linear_velocity.length()
	speed_kmh = speed * 3.6
	boost_ratio = _boost_energy / maxf(boost_capacity, 1.0)
	is_on_wall = grounded and absf(ground_normal.y) < 0.35

	is_drifting = want_drift and grounded and speed > 4.0

	# газ / тормоз / реверс / буст
	_step_drive(delta, throttle, want_boost, v_long, fwd)
	# боковое сцепление и занос
	_step_grip(delta, fwd, right)
	# руление (ось — нормаль контакта!)
	_step_steer(delta, steer_in, v_long, fwd, up)
	# ориентация корпуса: к стене на земле / к горизонту в воздухе
	_step_orientation(delta, up, fwd)
	# прижимная сила
	_step_downforce()
	# лимиты скорости (ТЗ)
	_clamp_speed(fwd, delta)

	if global_position.y < fall_limit_y:
		respawn()
	_update_boost_energy(delta)


# ════════════════════════ подвеска ════════════════════════
## 4 луча => (1) контакт-инфо для grip/steer/downforce, (2) пружины на тело.
##
## Запросы делаем через PhysicsDirectSpaceState3D.intersect_ray, а НЕ через
## RayCast3D-ноды: узлы RayCast3D остаются в сцене только как точки
## крепления (анкоры) — их позиция видна редакторе. Прямые space-queries:
##   * детерминированный порядок в рамках физ. тика (важно и для сервера
##     Спринта 3 — там не будет нод вообще, только эти запросы);
##   * работают одинаково на GodotPhysics3D и Jolt (в Jolt у выключенных
##     RayCast3D force_raycast_update() — источник тишины вместо данных);
##   * собственное тело исключено через `exclude`.
##
## Все силы нормализованы массой, поэтому «пружина 90g/м» одинаково работает
## и на 6 кг, и на 1400 кг (важно: тюнинг переживает смену коллайдеров).

func _step_suspension(delta: float) -> void:
	var hit_count := 0
	var normal_acc := Vector3.ZERO
	_max_comp = -10.0
	_susp.clear()

	var space := get_world_3d().direct_space_state
	var down: Vector3 = -global_transform.basis.y  # «вниз» кузова (вдоль local -Y)

	for ray in _rays:
		var mount: Vector3 = ray.global_position
		var entry := {"hit": false, "dist": susp_ray_length, "comp": -susp_ray_length, "mount": mount}
		var query := PhysicsRayQueryParameters3D.create(
			mount, mount + down * susp_ray_length, ARENA_LAYER, [get_rid()])
		query.collide_with_bodies = true
		query.collide_with_areas = false
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			var cp: Vector3 = hit["position"]
			# расстояние ВДОЛЬ оси подвески (down = local -Y кузова):
			# точка контакта ниже маунта => положительное расстояние
			var d: float = (cp - mount).dot(down)
			var contact_range := susp_rest_length + maxf(susp_travel, 0.45)
			if d <= contact_range and d > 0.02:
				var comp := clampf(susp_rest_length - d, -(susp_travel + 0.35), susp_travel)
				var cn: Vector3 = hit["normal"]
				if cn.y < 0.0:
					cn = -cn  # нормаль всегда «от грани к машине»
				entry["hit"] = true
				entry["dist"] = d
				entry["comp"] = comp
				hit_count += 1
				_max_comp = maxf(_max_comp, comp)
				normal_acc += cn * clampf(comp + susp_travel + 0.2, 0.02, 100.0)

				# ── пружина + демпфер ──
				# Асимметричный демпфер (гоночная классика): сжатие гасим
				# умеренно, ОТБОЙ душим сильно — иначе пружина возвращает
				# всю энергию приземления и машина прыгает «на батуте».
				var rel_v := linear_velocity.dot(cn)
				var damp := susp_damping * (susp_rebound_damp_mult if rel_v > 0.0 else 1.0)
				var f_mag := mass * _G * (susp_stiffness * comp - damp * clampf(rel_v, -40.0, 40.0))
				# потолки силы: без них демпфер на скорости касания даёт
				# «пшик» в сотни g и запускает машину в стратосферу;
				# pull-down (провис) жёстко ограничен снизу.
				f_mag = clampf(f_mag, -mass * _G * susp_pull_on_dangle, mass * _G * susp_max_g)
				apply_force(cn * f_mag, mount - global_position)
		_susp.append(entry)

	grounded = hit_count >= 1 and _max_comp > -0.22
	if grounded:
		_air_time = 0.0
		ground_normal = normal_acc.normalized() if normal_acc.length_squared() > 1e-9 else Vector3.UP
	else:
		_air_time += delta
		ground_normal = Vector3.UP


# ════════════════════════ тяга ════════════════════════

func _step_drive(delta: float, throttle: float, want_boost: bool, v_long: float, fwd: Vector3) -> void:
	var force := Vector3.ZERO
	if absf(throttle) > 0.02:
		var opposing := (throttle > 0.0 and v_long < -0.8) or (throttle < 0.0 and v_long > 0.8)
		if opposing:
			force = fwd * brake_force * throttle      # торможение движением: знак сам гасит v_long
		else:
			var mult := 1.0 if throttle > 0.0 else 0.6  # задний ход слабее
			force = fwd * engine_force * mult * throttle
	# буст (и на земле, и в воздухе — как в RL)
	var can_boost := _boost_energy > 0.5
	boost_active = want_boost and can_boost
	if boost_active:
		force += fwd * engine_force * boost_force_mult
	if force != Vector3.ZERO:
		apply_central_force(force)
	elif grounded and absf(throttle) < 0.02:
		var v := linear_velocity
		v -= fwd * v_long * clampf(coast_drag * delta, 0.0, 1.0)
		linear_velocity = v


## Энергия буста: копится на земле без заноса; в заносе — не восстанавливается (RL).
func _update_boost_energy(delta: float) -> void:
	if boost_active:
		_boost_energy = maxf(0.0, _boost_energy - boost_drain * delta)
	elif grounded and not is_drifting:
		_boost_energy = minf(boost_capacity, _boost_energy + boost_regen * delta)
	# Sprint 2 (готово): буст-пады на карте вызывают add_boost() (PickupBase)


func add_boost(amount: float) -> void:
	_boost_energy = clampf(_boost_energy + amount, 0.0, boost_capacity)


## Чтение запаса для смежных систем (Sprint 2: оружие тратит буст-энергию).
func get_boost_energy() -> float:
	return _boost_energy


# ════════════════════════ боковое сцепление ════════════════════════
## «Трение» реализовано гашением lateral-компоненты скорости (не через
## физматериал): детерминированно, fps-независимо, легко реплицируется.

func _step_grip(delta: float, fwd: Vector3, right: Vector3) -> void:
	if not grounded:
		return
	var k := grip_rate * (drift_grip_factor if is_drifting else 1.0)
	var v := linear_velocity
	var lat := v.dot(right)
	v -= right * lat * (1.0 - exp(-k * delta))
	if is_drifting:
		var vl := v.dot(fwd)
		v -= fwd * vl * (1.0 - exp(-drift_speed_leak * delta))
	linear_velocity = v


# ════════════════════════ руление ════════════════════════

func _step_steer(delta: float, steer_in: float, v_long: float, fwd: Vector3, up: Vector3) -> void:
	# сглаживание: быстрая прокачка, резкий возврат
	var rate := steer_input_rate if absf(steer_in) > absf(_steer) else steer_return_rate
	_steer = move_toward(_steer, steer_in, rate * delta)
	if absf(_steer) < 0.001 and absf(steer_in) < 0.001:
		return

	# ТЗ: лимит 35° сужается на высокой скорости. Квадратичная кривая:
	# полный руль до ~40% скорости, к 45 м/с остаётся 35% лимита (~12°).
	var sr := clampf(absf(v_long) / max_speed, 0.0, 1.0)
	var limit := deg_to_rad(steer_limit_deg) * lerpf(1.0, steer_high_speed_keep, sr * sr)
	var angle := _steer * limit * (drift_steering_bonus if is_drifting else 1.0)

	# велосипедная модель ω = v/L·tan(δ). В Godot поворот ВПРАВО = отрицательный
	# yaw вокруг Up; реверс автоматически инвертирует знак через sign(v_long).
	var v_eff := maxf(absf(v_long), 1.5)  # микро-доворот на месте для отзывчивости
	var sgn := signf(v_long) if absf(v_long) > 0.3 else 1.0
	var target_yaw := -sgn * (v_eff / wheelbase) * tan(angle)
	if is_drifting:
		target_yaw *= drift_yaw_bonus
	target_yaw = clampf(target_yaw, -max_yaw_rate, max_yaw_rate)
	if not grounded:
		target_yaw = -_steer * deg_to_rad(air_yaw_deg_per_s)

	# ось: нормаль контакта (на стене рулим «вдоль стены»), в воздухе — мировой Up
	var axis := ground_normal
	var w := angular_velocity
	var cur := w.dot(axis)
	var blend := 1.0 - exp(-turn_response * delta)
	var new_cur := lerpf(cur, target_yaw, blend)
	angular_velocity = w + axis * (new_cur - cur)
	# pitch/roll-компоненты здесь не трогаем — ими заведует _step_orientation


# ════════════════════════ ориентация ════════════════════════

func _step_orientation(delta: float, up: Vector3, fwd: Vector3) -> void:
	var w := angular_velocity
	if grounded:
		# yaw вокруг нормали контакта — суверенная зона _step_steer;
		# здесь правим только pitch/roll (компоненты ⊥ нормали)
		var yaw_axis := ground_normal
		var yaw_comp := yaw_axis * w.dot(yaw_axis)
		var ortho := w - yaw_comp
		var err := up.cross(ground_normal)  # ->0 когда корпус выровнен по грани
		var target := err * (contact_align_response * 1.7)
		var o := ortho.lerp(target, 1.0 - exp(-contact_align_response * delta))
		o -= fwd * o.dot(fwd) * clampf(anti_roll_rate * delta, 0.0, 1.0)  # анти-ролл wall-ride
		angular_velocity = yaw_comp + o
	else:
		# воздух: yaw сохраняем, pitch/roll мягко тянем к горизонту
		var yaw_w := Vector3.UP * w.dot(Vector3.UP)
		var tilt_up := up
		var target_ortho := Vector3.ZERO
		if tilt_up.angle_to(Vector3.UP) > deg_to_rad(air_align_deadzone_deg):
			target_ortho = tilt_up.cross(Vector3.UP) * air_align_speed  # |cross|~sin(tilt): пропорц. рассогласованию
		var non_yaw := w - yaw_w
		angular_velocity = yaw_w + non_yaw.lerp(target_ortho, 1.0 - exp(-air_stab_response * delta))


# ════════════════════════ прижим / лимиты ════════════════════════
## Downforce растёт с квадратом скорости (ТЗ) => на изогнутых стенах машина
## «прилипает» только на разгоне — скилл-момент, как в RL, а не «магнит».

func _step_downforce() -> void:
	if not grounded:
		return
	var ratio := clampf(linear_velocity.length() / max_speed, 0.0, 1.0)
	var hold := ratio * ratio + downforce_min_hold
	if boost_active:
		hold += downforce_boost_bonus
	apply_central_force(-ground_normal * mass * _G * downforce_strength * hold)


func _clamp_speed(fwd: Vector3, delta: float) -> void:
	var cap := max_speed * (boost_multiplier if boost_active else 1.0)
	var v := linear_velocity
	var vl := v.dot(fwd)
	if absf(vl) > cap:
		# мягко «обкусываем» продольную: боковая остаётся — занос живёт
		v -= fwd * signf(vl) * (absf(vl) - cap) * clampf(12.0 * delta, 0.0, 1.0)
	elif vl < -reverse_max_speed and not boost_active:
		v -= fwd * (vl + reverse_max_speed) * clampf(12.0 * delta, 0.0, 1.0)
	# абсолютный предохранитель (защита от выстрелов тримеша/багов)
	var hard_cap := max_speed * boost_multiplier + 10.0
	if v.length_squared() > hard_cap * hard_cap:
		v = v.normalized() * hard_cap
	linear_velocity = v


# ════════════════════════ спавн-поинты (заглушки DoD 4) ════════════════════════

func respawn(spawn: Node3D = null) -> void:
	_respawning = false
	if spawn == null:
		spawn = _nearest_spawn()
	if spawn:
		var pos := spawn.global_position + Vector3(0.0, 1.7, 0.0)
		global_position = pos
		var flat := Vector3(pos.x, 0.0, pos.z)
		if flat.length_squared() > 4.0:
			# лицом к центру арены (только yaw, чтобы не «задрать нос» на спавне)
			var dir := -flat.normalized()
			rotation = Vector3(0.0, atan2(-dir.x, -dir.z), 0.0)
	else:
		global_position = Vector3(0.0, 3.0, 0.0)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_steer = 0.0
	_susp.clear()  # гасим «пружинный чих»: до следующего кадра подвеска пересчитается
	respawned.emit()


func _nearest_spawn() -> Node3D:
	var best: Node3D = null
	var best_d := 1e18
	for n in get_tree().get_nodes_in_group("arena_spawn"):
		var m := n as Node3D
		if m == null:
			continue
		var d := m.global_position.distance_squared_to(global_position)
		if d < best_d:
			best_d = d
			best = m
	return best


## Сокеты под оружие/тюнинг Sprint 2 (DoD 4). GunMountPoint — штатный сокет
## пушки (позиция «крыло/крыша» по ТЗ); WeaponSocket_L/R/C — место под второй
## ствол/тюнинг (гараж Sprint 4).
func get_hardpoint(socket_name: String) -> Node3D:
	if _hardpoints == null:
		_hardpoints = get_node_or_null("Hardpoints") as Node3D
	return _hardpoints.get_node_or_null(socket_name) if _hardpoints else null


## ── Sprint 2: монтируемое оружие ──
## Спавнит оружие из сцены и вешает его ДИТИМ узлом на сокет (ТЗ п.1).
func mount_weapon(weapon: Node3D, socket_name: String = "GunMountPoint") -> bool:
	if weapon == null:
		return false
	var socket := get_hardpoint(socket_name)
	if socket == null:
		push_warning("ArcadeVehicle: сокет '%s' не найден — оружие не смонтировано" % socket_name)
		return false
	weapon.set("vehicle", self)  # до add_child: _ready должен увидеть носителя
	socket.add_child(weapon)
	_weapons.append(weapon)
	weapon_mounted.emit(weapon)
	return true


func get_weapons() -> Array:
	return _weapons


func get_health() -> Node:
	return _health


func get_unit_id() -> String:
	return unit_id


## Огонь извне (боты Sprint 3 / нет-команды) — форвард на все стволы.
func set_external_fire(on: bool) -> void:
	for w in _weapons:
		if w != null and w.has_method("set_external_fire"):
			w.set_external_fire(on)


# ════════════════════════ визуал колёс (в _process — не дёргает физику) ════════════════════════

func _process(delta: float) -> void:
	if _wheels_vis.size() == 4 and _susp.size() == 4:
		for i in 4:
			var wheel := _wheels_vis[i]
			var entry: Dictionary = _susp[i]
			var target_y := -susp_rest_length - 0.1
			if entry.get("hit", false):
				var d: float = entry["dist"]
				target_y = -(clampf(d, susp_rest_length - susp_travel - 0.05, susp_rest_length + 0.35) - _WHEEL_R) - 0.1
			wheel.position.y = lerpf(wheel.position.y, target_y, clampf(20.0 * delta, 0.0, 1.0))
		var vis_angle := _steer * deg_to_rad(steer_limit_deg) * 0.9
		for k in [0, 1]:
			if k < _wheel_yaws.size() and _wheel_yaws[k]:
				_wheel_yaws[k].rotation.y = lerpf(_wheel_yaws[k].rotation.y, vis_angle, clampf(14.0 * delta, 0.0, 1.0))
	_wheel_spin = fmod(_wheel_spin + linear_velocity.length() / _WHEEL_R * delta, TAU)
	for i in _wheels_vis.size():
		var spin := _wheels_vis[i].get_node_or_null("Steer/Spin") as Node3D
		if spin:
			spin.rotation.x = -_wheel_spin


# ════════════════════════ Sprint 3: скелет нет-стейта ════════════════════════
## Модель авторитарного сервера (ТЗ): клиент предсказывает физику локальной
## машины, сервер валидирует попадания/HP/очки (Спринт 2) и реплицирует
## состояние. Удалённые машины: apply_net_state + dead-reckoning между снапшотами.

func get_net_state() -> Dictionary:
	var tr := global_transform
	var e := tr.basis.get_euler()
	return {
		"p": [tr.origin.x, tr.origin.y, tr.origin.z],
		"e": [e.x, e.y, e.z],
		"v": [linear_velocity.x, linear_velocity.y, linear_velocity.z],
		"b": _boost_energy,
		"d": is_drifting,
		# Sprint 2: боёвка (HP — авторитарно на сервере; тут — для реплея/ошибки)
		"dead": is_dead(),
		"hp": _health.current_health if _health != null else 0.0,
		"w": [],  # TODO Sprint 3: [gun.get_net_state() for gun in _weapons]
	}


func apply_net_state(s: Dictionary) -> void:
	# TODO Sprint 3: интерполяция между снапшотами вместо телепорта
	if s.has("p"):
		global_position = Vector3(s["p"][0], s["p"][1], s["p"][2])
	if s.has("e"):
		global_rotation = Vector3(s["e"][0], s["e"][1], s["e"][2])
	if s.has("v"):
		linear_velocity = Vector3(s["v"][0], s["v"][1], s["v"][2])


## Удалённая машина: симулировать локальную физику не нужно (визуал + reconcile)
func set_net_authoritative(p_enabled: bool) -> void:
	control_enabled = not p_enabled
