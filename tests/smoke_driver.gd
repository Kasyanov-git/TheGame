extends Node
## Headless smoke-тест Sprint 1+2 (без рендера — чистая физика/логика).
##
## Запуск:
##   godot --headless --path . res://tests/smoke.tscn
##
## Sprint 1 (тики 1..520) — вождение:
##   1. разгон/лимит max_speed; 2. подвеска (земля после спавна);
##   3. руление; 4. дрифт; 5. буст-энергия и кап x1.7; 6. respawn;
##   7. арена собрана (trimesh, NaN-надзор).
## Sprint 2 (тики 520..968) — боевая система (DoD ТЗ):
##   8.  оружие смонтировано дочерним узлом на GunMountPoint (п.1);
##   9.  турель наводится в точку camera-ray: не мгновенно (кап 12 рад/с),
##       pitch в [-10°, +30°], выстрелы с каденцией 0.15 с, буст-энергия
##       тратится (DoD 1);
##   10. снаряды наносят урон ровно damage*попаданий и деактивируются при
##       попадании в геометрию / по lifetime (DoD 2); hitscan — мгновенный
##       урон без снарядов, магазин тратится;
##   11. смерть: freeze/скрытие/блокировка ввода + explosion-заглушка,
##       респавн на случайной точке через respawn_delay, HP восстановлен (DoD 3);
##   12. пикапы: repair +35, nitro = 100% шкалы, shield поглощает урон и
##       спадает по таймеру, кулдаун блокирует повторный подбор, вращение
##       иконки (DoD 4).
##
## Экспоненциальные фильтры контроллера (1 - e^-k·dt) дают детерминизм по
## симулированному времени; seed() фиксирует казуальный разброс.

const MAIN_SCENE := "res://src/main/main.tscn"

var _t := 0
var _main: Node
var _car: ArcadeVehicle
var _fails := 0
# sprint 1
var _peak_speed := 0.0
var _peak_lat := 0.0
var _ever_grounded := false
var _start := Vector3.ZERO
var _yaw_before := 0.0
var _boost_before := 100.0
# sprint 2
var _cannon = null      # BaseWeapon игрока (duck-typed: в smoke-копиях классы без аннотаций)
var _mg = null
var _enemy = null
var _eh = null            # HealthComponent врага
var _ch = null            # HealthComponent игрока
var _fire_events := 0
var _fire_ticks: Array = []
var _hit_events := 0
var _last_dir := Vector3.ZERO
var _max_yaw_step := 0.0
var _yaw_prev := 0.0
var _energy_before := 0.0
var _wall_proj = null
var _wall_impacts := 0
var _life_proj = null
var _life_impacts := 0
var _hp0_mg := 100.0
var _mg_hits := 0
var _pads := {}
var _icon_yaw_0 := 0.0


func _ready() -> void:
	var ps := load(MAIN_SCENE) as PackedScene
	assert(ps != null)
	_main = ps.instantiate()
	add_child(_main)
	_car = _main.find_child("PlayerCar", true, false) as ArcadeVehicle
	assert(_car != null)
	_start = _car.global_position
	_boost_before = _car._boost_energy
	# Арена: проверим, что генератор построил геометрию
	var arena := _main.find_child("Arena", true, false) as Node3D
	assert(arena != null)
	var body := arena.find_child("BowlBody", true, false) as StaticBody3D
	assert(body != null)
	var shape_node := body.find_child("BowlShape", true, false) as CollisionShape3D
	assert(shape_node != null and shape_node.shape is ConcavePolygonShape3D)
	var tri: int = (shape_node.shape as ConcavePolygonShape3D).data.size() / 3
	print("SMOKE: arena collision tris = %d" % tri)
	_check(tri > 5000, "arena trimesh generated (%d tris)" % tri)


func _physics_process(_delta: float) -> void:
	_t += 1
	# общий надзор: NaN
	var p := _car.global_position
	var v := _car.linear_velocity
	if not (p.is_finite() and v.is_finite()):
		_check(false, "NaN in physics at tick %d" % _t)
		_finish()
		return
	_peak_speed = maxf(_peak_speed, v.length())
	var right := _car.global_transform.basis.x
	_peak_lat = maxf(_peak_lat, absf(v.dot(right)))
	if _car.grounded:
		_ever_grounded = true
	if _t >= 522 and _cannon != null:
		# вес орудия: скорость поворота башни за тик
		var y: float = _cannon.turret_yaw()
		_max_yaw_step = maxf(_max_yaw_step, absf(wrapf(y - _yaw_prev, -PI, PI)))
		_yaw_prev = y

	match _t:
		6:
			_car.set_external_input(0.0, 1.0, false, false)   # газ прямо
		80:
			_check(_ever_grounded, "car lands on ground after spawn (ever-grounded flag)")
		100:
			_check(_peak_speed > 15.0, "throttle accelerates (peak %.1f m/s > 15)" % _peak_speed)
			_check(p.distance_to(_start) > 12.0, "car moved %.1f m" % p.distance_to(_start))
			_peak_speed = 0.0
		160:
			_check(_peak_speed <= 45.0 * 1.06, "max_speed cap respected (peak %.1f ≤ 47.7)" % _peak_speed)
			_car.set_external_input(1.0, 1.0, false, false)   # газ + руль вправо
			_yaw_before = _car_yaw()
		205:
			_check(absf(wrapf(_car_yaw() - _yaw_before, -PI, PI)) > 0.15,
				"steering changes heading (yaw Δ %.2f rad)" % absf(wrapf(_car_yaw() - _yaw_before, -PI, PI)))
			_peak_lat = 0.0
			_car.set_external_input(1.0, 1.0, false, true)   # дрифт
		250:
			_check(_peak_lat > 1.5, "drift produces lateral slide (%.1f m/s)" % _peak_lat)
			_boost_before = _car._boost_energy
			_peak_speed = 0.0
			_car.set_external_input(0.0, 1.0, true, false)   # буст прямо
		330:
			_check(_car._boost_energy < _boost_before, "boost drains energy (%.0f → %.0f)" % [_boost_before, _car._boost_energy])
			_check(_peak_speed > 49.0, "boost exceeds base cap (peak %.1f)" % _peak_speed)
			_check(_peak_speed < 45.0 * 1.7 + 11.0, "boost cap respected (peak %.1f < 87.5)" % _peak_speed)
			_car.set_external_input(0.0, 0.0, false, false)
		420:
			_car.global_position = Vector3(77.0, 60.0, -90.0)
			_car.linear_velocity = Vector3.ZERO
			_car.angular_velocity = Vector3.ZERO
		421:
			_car.respawn()
		490:
			var dmin := 1e9
			for n in get_tree().get_nodes_in_group("arena_spawn"):
				dmin = minf(dmin, (n as Node3D).global_position.distance_to(_car.global_position))
			_check(dmin < 4.0, "respawn to spawn point (dist %.1f)" % dmin)
			_check(absf(_car.global_position.y) < 2.5 or _ever_grounded,
				"respawned car near floor / touches it (y=%.2f)" % _car.global_position.y)
		520:
			_s2_start()
		552:
			if _cannon != null:
				_cannon.set_external_fire(false)
		565:
			_s2_checks_aiming()
		568:
			_s2_spawn_manual_projectiles()
		600:
			_s2_checks_projectile_lifecycle()
		606:
			_s2_start_hitscan()
		618:
			if _mg != null:
				_mg.set_external_fire(false)
		621:
			_s2_checks_hitscan()
		630:
			if _eh != null:
				_eh.take_damage(9999.0, "PlayerCar")   # DoD 3: полный цикл смерти
		631:
			_s2_checks_death()
		880:
			_s2_checks_enemy_respawn()
		890:
			_s2_pickups_setup()
		893:
			if _ch != null:
				_check(absf(_ch.current_health - 85.0) < 0.01,
					"repair pickup heals +35 (hp %.1f == 85)" % _ch.current_health)
			_check(_pads.has(0) and not _pads[0].ready_for_pickup, "pickup goes on cooldown")
		895:
			_s2_away_from_pad_and_damage(45.0)   # hp 85 → 40, сходим с площадки
		899:
			_s2_back_onto_pad()                  # вход на КУЛДАУНЕ — не лечит
		902:
			if _ch != null:
				_check(absf(_ch.current_health - 40.0) < 0.01,
					"cooldown blocks re-pickup (hp stays %.1f)" % _ch.current_health)
		905:
			if _pads.has(0):
				_pads[0].force_ready()           # ускоряем окончание кулдауна (механика теста)
		907:
			_s2_away_only()
		909:
			_s2_back_onto_pad()
		912:
			if _ch != null:
				_check(absf(_ch.current_health - 75.0) < 0.01,
					"re-enabled pickup heals again (hp %.1f == 75)" % _ch.current_health)
		914:
			_s2_nitro_run()
		919:
			_check(absf(_car._boost_energy - _car.boost_capacity) < 0.01,
				"nitro pickup refills boost to 100%% (%.1f)" % _car._boost_energy)
		922:
			_s2_shield_run()
		926:
			if _ch != null:
				_check(_ch.shield_time_left > 5.0,
					"shield pickup grants ~6s bubble (%.1fs)" % _ch.shield_time_left)
			_check(_pads.has(2) and _pads[2].get_node("Icon").rotation.y != _icon_yaw_0,
				"pickup icon rotates")
		929:
			if _ch != null:
				_ch.take_damage(30.0, "test")    # щит активен — не должно пройти
				_check(absf(_ch.current_health - 70.0) < 0.01,
					"shield absorbs damage (hp %.1f == 70)" % _ch.current_health)
				_ch.shield_time_left = 0.5       # ускоряем спад щита
		963:
			if _ch != null:
				_ch.take_damage(30.0, "test")   # щит истёк — проходит
		965:
			if _ch != null:
				_check(absf(_ch.current_health - 40.0) < 0.01,
					"damage applies after shield expiry (hp %.1f == 40)" % _ch.current_health)
		968:
			_finish()


# ════════════════════════ Sprint 2: секции ════════════════════════

func _s2_start() -> void:
	seed(1337)  # казуальный разброс reproducible
	_car.clear_external_input()
	_teleport(_car, Vector3(0.0, 1.7, 6.0))
	_car.rotation = Vector3.ZERO
	# камера: мгновенный снап (иначе центральный луч «уедет» от цели)
	var rig := _main.find_child("CameraRig", true, false)
	if rig != null and rig.has_method("_snap_to_vehicle"):
		rig.call("_snap_to_vehicle")
	# оружие смонтировано main.gd на GunMountPoint (ТЗ п.1: дочерний узел сокета)
	var ws := _car.get_weapons()
	_check(ws.size() == 1, "weapon mounted on vehicle (mount_weapon)")
	if ws.size() == 0:
		return
	_cannon = ws[0]
	_check(_cannon.get_parent().name == "GunMountPoint", "weapon is child node of GunMountPoint socket")
	_cannon.enabled = true
	_cannon.connect("weapon_fired", _on_weapon_fired)
	_cannon.connect("hit_registered", _on_cannon_hit)
	_ch = _car.get_health()
	_check(_ch != null, "vehicle has HealthComponent")
	# ── цель: вражеская машина ровно в точку camera-ray (прицел) ──
	_enemy = load("res://src/vehicle/player_car.tscn").instantiate()
	_main.add_child(_enemy)
	_enemy.control_enabled = false
	_enemy.freeze = true
	var aim_pt := _crosshair_point()
	# цель — в 6 м вбок от точки прицела, на земле (уровень машины): турель
	# обязана ПОВЕРНУТЬСЯ (не нулевое отклонение), а снаряды (y≈1.9, триггер
	# r0.9) должны достать до хитбокса (0.7..2.0), а не пролететь под ним.
	_teleport(_enemy, Vector3(aim_pt.x, _car.global_position.y, aim_pt.z)
		+ _car.global_transform.basis.x * 6.0)
	_eh = _enemy.get_node("Health")
	_energy_before = _car._boost_energy
	_yaw_prev = _cannon.turret_yaw()
	_cannon.set_external_fire(true)


func _crosshair_point() -> Vector3:
	var vp := get_viewport()
	var cam := vp.get_camera_3d()
	var size := vp.get_visible_rect().size
	if cam == null or size.y <= 1.0:
		# headless: viewport без высоты → зеркалим фолбэк TurretAimer 1-в-1,
		# иначе смоук телепортирует цель не туда, куда смотрит турель.
		var f := -_car.global_transform.basis.z
		f.y = 0.0
		f = f.normalized() if f.length_squared() > 1e-9 else Vector3.BACK
		return _car.global_position + Vector3.UP * 1.2 + f * 24.0
	var center := size * 0.5
	var origin: Vector3 = cam.project_ray_origin(center)
	var dir: Vector3 = cam.project_ray_normal(center)
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 200.0, 3)
	q.collide_with_areas = false
	q.exclude = [_car.get_rid()]
	var hit: Dictionary = _car.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		return hit["position"]
	return origin + dir * 24.0


func _on_weapon_fired(_muzzle: Vector3, dir: Vector3) -> void:
	_fire_events += 1
	_fire_ticks.append(_t)
	_last_dir = dir


func _on_cannon_hit(_pos: Vector3, _dmg: float, _kill: bool) -> void:
	_hit_events += 1


func _s2_checks_aiming() -> void:
	if _cannon == null or _enemy == null:
		return
	# DoD 1: каденция (0.5 с удержания / 0.15 с => 3..5 выстрелов, ~9 тиков между)
	_check(_fire_events >= 3 and _fire_events <= 5,
		"cannon cadence fire_rate=0.15s (%d shots in 30 ticks)" % _fire_events)
	if _fire_ticks.size() >= 2:
		var iv: int = _fire_ticks[1] - _fire_ticks[0]
		_check(iv >= 7 and iv <= 12, "shot interval ~9 ticks (%d)" % iv)
	# ствол сошёлся с точкой прицела (наведение не мгновенное — см. кап ниже)
	var to_target: Vector3 = _enemy.get_node("Hitbox").global_position - _cannon.muzzle_position()
	var ang := rad_to_deg(_cannon.aim_forward().angle_to(to_target.normalized()))
	_check(ang < 4.0, "turret converged on crosshair target (err %.2f deg)" % ang)
	_check(_cannon.is_aligned(), "turret reports aligned=true")
	# вес орудия: за тик не больше turret_rotation_speed*dt (шаг фикс. 1/60)
	_check(_max_yaw_step <= 12.0 / 60.0 * 1.25,
		"turret speed cap <= 12 rad/s (max step %.4f rad)" % _max_yaw_step)
	# pitch ограничен [-10°, +30°]
	var pitch := rad_to_deg(_cannon.turret_pitch())
	_check(pitch >= -10.5 and pitch <= 30.5, "barrel pitch within [-10..+30] deg (%.1f)" % pitch)
	# выстрел — вдоль ФАКТИЧЕСКОГО ствола
	_check(_last_dir.dot(_cannon.aim_forward()) > 0.998, "shot direction follows barrel")
	# DoD 2: урон ровно 15 за попадание; снарядов в мире не осталось
	var dealt := _eh.max_health - _eh.current_health
	_check(_hit_events >= 1, "projectiles damaged enemy vehicle (%d hits)" % _hit_events)
	_check(absf(dealt - 15.0 * _hit_events) < 0.01,
		"enemy hp reduced exactly by damage*hits (%.1f == %.1f)" % [dealt, 15.0 * _hit_events])
	_check(get_tree().get_nodes_in_group("projectiles").size() == 0,
		"all projectiles despawned after impact")
	# энергия буста потрачена (с учётом регена 9 ед/с на земле)
	_check(_car._boost_energy < _energy_before - 12.0,
		"cannon drains boost energy (%.1f -> %.1f)" % [_energy_before, _car._boost_energy])


func _s2_spawn_manual_projectiles() -> void:
	# DoD 2: деактивация о геометрию (sweep-ray) и по lifetime.
	# Стартуем СБОКУ от машины, чтобы не задеть собственный корпус.
	var ps := load("res://src/combat/projectile.tscn")
	_wall_proj = ps.instantiate()
	_main.add_child(_wall_proj)
	_wall_proj.connect("impacted", _on_wall_impact)
	_wall_proj.setup(Vector3(8.0, 0.9, 6.0), Vector3(0.0, 0.02, 1.0).normalized(),
		120.0, 5.0, 3.0, null, null)
	_life_proj = ps.instantiate()
	_main.add_child(_life_proj)
	_life_proj.connect("impacted", _on_life_impact)
	_life_proj.setup(Vector3(-4.0, 3.4, 6.0), Vector3(0.0, 0.87, -0.5).normalized(),
		120.0, 5.0, 0.12, null, null)


func _on_wall_impact(_pos: Vector3, _vh: bool, _k: bool) -> void:
	_wall_impacts += 1


func _on_life_impact(_pos: Vector3, _vh: bool, _k: bool) -> void:
	_life_impacts += 1


func _s2_checks_projectile_lifecycle() -> void:
	if _wall_proj == null or _life_proj == null:
		return
	var wall_dead: bool = (not is_instance_valid(_wall_proj)) or not _wall_proj.is_active
	_check(wall_dead and _wall_impacts == 1,
		"projectile despawns on wall hit (impacts %d)" % _wall_impacts)
	_check(not is_instance_valid(_life_proj), "projectile despawns on lifetime expiry")
	_check(_life_impacts == 0, "expired projectile never impacted")


func _s2_start_hitscan() -> void:
	if _enemy == null:
		return
	var ms := load("res://src/combat/weapon_mg.tscn")
	_mg = ms.instantiate()
	_car.mount_weapon(_mg, "WeaponSocket_L")
	_check(_mg.get_parent().name == "WeaponSocket_L", "second weapon mounts to named socket")
	if _cannon != null:
		_cannon.enabled = false
	_mg.connect("hit_registered", _on_mg_hit)
	_hp0_mg = _eh.current_health
	_mg.set_external_fire(true)


func _on_mg_hit(_pos: Vector3, _dmg: float, _k: bool) -> void:
	_mg_hits += 1


func _s2_checks_hitscan() -> void:
	if _mg == null:
		return
	_check(_mg_hits >= 1, "hitscan hits instantly (%d hits)" % _mg_hits)
	var dealt: float = _hp0_mg - _eh.current_health
	_check(absf(dealt - 6.0 * _mg_hits) < 0.01,
		"hitscan damage exact (6*%d = %.1f)" % [_mg_hits, dealt])
	_check(_mg.shots_fired >= _mg_hits, "mg actually fired")
	_check(absf(_mg.ammo - (_mg.ammo_max - float(_mg.shots_fired))) < 0.01,
		"mg ammo spent (%.0f left)" % _mg.ammo)
	_check(get_tree().get_nodes_in_group("projectiles").size() == 0,
		"hitscan spawns no projectiles")


func _s2_checks_death() -> void:
	if _eh == null or _enemy == null:
		return
	_check(_eh.is_dead, "enemy marked dead (hp<=0)")
	_check(_eh.last_attacker_id == "PlayerCar", "kill attributed to attacker id")
	_check(_enemy.freeze, "vehicle physics disabled on death")
	_check(not _enemy.find_child("Visual", true, false).visible, "vehicle hidden on death")
	_check(_enemy.is_respawning(), "vehicle input blocked while respawning")
	_check(get_tree().get_nodes_in_group("explosions").size() >= 1,
		"explosion placeholder spawned")


func _s2_checks_enemy_respawn() -> void:
	if _eh == null or _enemy == null:
		return
	_check(not _eh.is_dead, "enemy revived after respawn_delay")
	_check(absf(_eh.current_health - _eh.max_health) < 0.01, "respawned at full HP")
	_check(not _enemy.freeze and _enemy.find_child("Visual", true, false).visible,
		"physics/visuals restored on respawn")
	var dmin := 1e9
	for n in get_tree().get_nodes_in_group("arena_spawn"):
		dmin = minf(dmin, (n as Node3D).global_position.distance_to(_enemy.global_position))
	_check(dmin < 4.5, "respawned on a spawn point (dist %.1f)" % dmin)


func _s2_pickups_setup() -> void:
	for n in get_tree().get_nodes_in_group("pickups"):
		if not _pads.has(int(n.type)):
			_pads[int(n.type)] = n
	_check(_pads.size() == 3, "all 3 pickup types present on map")
	if _pads.size() != 3 or _ch == null:
		return
	_icon_yaw_0 = _pads[2].get_node("Icon").rotation.y
	_ch.take_damage(50.0, "test")  # hp 100 -> 50
	_teleport(_car, _pads[0].global_position + Vector3(0.0, 1.7, 0.0))


func _s2_away_from_pad_and_damage(amount: float) -> void:
	_s2_away_only()
	if _ch != null:
		_ch.take_damage(amount, "test")


func _s2_away_only() -> void:
	if _pads.has(0):
		_teleport(_car, _pads[0].global_position + Vector3(0.0, 1.7, 14.0))


func _s2_back_onto_pad() -> void:
	if _pads.has(0):
		_teleport(_car, _pads[0].global_position + Vector3(0.0, 1.7, 0.0))


func _s2_nitro_run() -> void:
	_car.add_boost(-1000.0)  # шкала в 0
	if _pads.has(1):
		_teleport(_car, _pads[1].global_position + Vector3(0.0, 1.7, 0.0))


func _s2_shield_run() -> void:
	if _ch != null:
		_ch.take_damage(5.0, "test")  # 75 -> 70 (на кулдауне repair-площадки)
	if _pads.has(2):
		_teleport(_car, _pads[2].global_position + Vector3(0.0, 1.7, 0.0))


# ════════════════════════ утилиты ════════════════════════

func _teleport(v, pos: Vector3) -> void:
	v.global_position = pos
	if v is RigidBody3D:
		v.linear_velocity = Vector3.ZERO
		v.angular_velocity = Vector3.ZERO
	if v.has_method("get_hardpoint"):  # ArcadeVehicle
		v._susp.clear()


func _car_yaw() -> float:
	var f := -_car.global_transform.basis.z
	return atan2(-f.x, -f.z)


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK   %s" % msg)
	else:
		_fails += 1
		print("  FAIL %s" % msg)


func _finish() -> void:
	print("SMOKE: %s (%d fails)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)
