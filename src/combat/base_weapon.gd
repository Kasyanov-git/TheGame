class_name BaseWeapon
extends Node3D
## Базовое монтируемое оружие (Sprint 2, п.1–2 ТЗ).
##
## Жизненный цикл: ArcadeVehicle.mount_weapon() создаёт экземпляр из сцены-
## пресета (weapon_cannon.tscn / weapon_mg.tscn) и прикрепляет его ДИТИМ узлом
## к сокету GunMountPoint на корпусе (ТЗ: «Оружие спавнится и прикрепляется
## к этой точке как дочерний узел»).
##
## Структура пивотов (если пресет их не объявил — строится кодом):
##   Turret (yaw, ограничена скоростью) -> Barrel (pitch −10°…+30°) -> Muzzle.
## Наведение — TurretAimer (камера-рейкаст в точку прицела).
##
## Стрельба:
##   * PROJECTILE — «Arcade Fast Projectile» (ТЗ-основной): снаряд 120 м/с,
##     щедрый сферический триггер 0.9 м, lifetime 3.0 с, гибнет при попадании.
##   * HITSCAN    — мгновенный рейкаст от дула (ТЗ: «легкое скорострельное
##     оружие»); RayCast3D-семантика, но через direct-space-запрос
##     (урок Sprint 1: детерминизм GodotPhysics/Jolt + перенос на сервер).
## Ресурс: BOOST_ENERGY (тратим шкалу буста машины — связка с Sprint 1)
## или AMMO (магазин + авто-восстановление).
##
## Сигналы (хуки для UI/VFX/SFX — ТЗ п.5):
##   * weapon_fired(muzzle_position, direction) — вспышка/звук;
##   * hit_registered(target_position, damage, is_kill) — хитмаркер/цифры урона.
##
## Неткод (Sprint 3): состояние турели реплицируется (get_net_state),
## внешний огонь для ботов — set_external_fire().

signal weapon_fired(muzzle_position: Vector3, direction: Vector3)
signal hit_registered(target_position: Vector3, damage: float, is_kill: bool)

enum FireType { PROJECTILE, HITSCAN }
enum ResourceMode { NONE, BOOST_ENERGY, AMMO }

const _AIMER_SCRIPT := preload("res://src/combat/turret_aimer.gd")
## ^ preload, а не «TurretAimer.new()»: runtime-сборки без редакторского
## class-cache резолвят custom-class по имени не всегда (наш wasm-CI это ловит).

const ARENA_LAYER := 1
const VEHICLES_LAYER := 2
const HITBOX_LAYER := 8

# ─────────────────────────── Тюнинг (экспорты; дефолты = ТЗ) ───────────────────────────
@export var fire_type: FireType = FireType.PROJECTILE
@export var fire_rate := 0.15              ## ТЗ: с между выстрелами
@export var damage := 15.0                  ## ТЗ: 15 HP
@export var spread_degrees := 1.5           ## ТЗ: казуальный разброс
@export_group("Resource")
@export var resource_mode: ResourceMode = ResourceMode.BOOST_ENERGY
@export var energy_cost := 6.0              ## ед. буста за выстрел (BOOST_ENERGY)
@export var ammo_max := 80.0                ## (AMMO)
@export var ammo_regen := 30.0              ## ед/с (AMMO)
@export var ammo_regen_delay := 0.6         ## с прострела до старта регена
@export_group("Projectile")
@export var projectile_speed := 120.0       ## ТЗ: 120 м/с
@export var projectile_lifetime := 3.0      ## ТЗ: 3.0 с
@export var projectile_scene: PackedScene = null  ## null -> стандартный снаряд
@export_group("Hitscan")
@export var hitscan_range := 200.0          ## м
@export_group("Turret")
@export var turret_rotation_speed := 12.0   ## ТЗ: рад/с (вес орудия)
@export var min_pitch_deg := -10.0          ## ТЗ: −10°
@export var max_pitch_deg := 30.0           ## ТЗ: +30°
@export var aim_snap_radius := 12.0         ## м, aim assist по хитбоксам
@export var muzzle_path: NodePath = ^"Turret/Barrel/Muzzle"
@export var enabled := true                 ## тумблер (выдачи оружия/отладка)

# ─────────────────────────── Публичное состояние ───────────────────────────
var vehicle = null                         ## кто носит (Variant: weapon-классы не знают ArcadeVehicle)
var ammo := 0.0                            ## текущий магазин (AMMO)
var shots_fired := 0                       ## статистика/смоук-тесты

var _turret: Node3D = null
var _barrel: Node3D = null
var _muzzle: Node3D = null
var _aimer: TurretAimer = null
var _cool := 0.0
var _idle_t := 0.0
var _ext_fire := false
var _flash: MeshInstance3D = null
var _flash_t := 0.0


func _ready() -> void:
	_ensure_structure()
	_aimer = _AIMER_SCRIPT.new()
	_aimer.name = "TurretAimer"
	add_child(_aimer)
	_aimer.configure(_turret, _barrel, _muzzle, vehicle)
	_aimer.rotation_speed = turret_rotation_speed
	_aimer.min_pitch_deg = min_pitch_deg
	_aimer.max_pitch_deg = max_pitch_deg
	_aimer.snap_radius = aim_snap_radius
	ammo = ammo_max


## Связь с носителем. ArcadeVehicle.mount_weapon ставит `weapon.vehicle`
## ДО add_child (чтобы _ready успел подхватить якорь); повторный вызов
## перепривязывает узел (garage swap на Sprint 4).
func mount_on(host: Node) -> void:
	vehicle = host
	if _aimer != null:
		_aimer.configure(_turret, _barrel, _muzzle, vehicle)


## Внешний огонь (боты Sprint 3 / симуляция нет-инпутов) — как held LMB.
func set_external_fire(p_on: bool) -> void:
	_ext_fire = p_on


func aim_forward() -> Vector3:
	return _aimer.get_forward() if _aimer != null else -global_transform.basis.z


func is_aligned() -> bool:
	return _aimer != null and _aimer.aligned


## Состояние турели (HUD/SFX/смоук-тесты).
func turret_yaw() -> float:
	return _aimer.yaw if _aimer != null else 0.0


func turret_pitch() -> float:
	return _aimer.pitch if _aimer != null else 0.0


func aim_point() -> Vector3:
	return _aimer.aim_point if _aimer != null else global_position


func muzzle_position() -> Vector3:
	return _muzzle.global_position if _muzzle != null else global_position


# ════════════════════════ основной тик ════════════════════════

func _physics_process(delta: float) -> void:
	if not enabled:
		return
	_cool = maxf(0.0, _cool - delta)
	# реген магазина после паузы
	if resource_mode == ResourceMode.AMMO and ammo < ammo_max:
		_idle_t += delta
		if _idle_t >= ammo_regen_delay:
			ammo = minf(ammo_max, ammo + ammo_regen * delta)
	# вспышка дула (визуал живёт в _process-тактах, гаснет сам)
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash != null:
			_flash.visible = _flash_t > 0.0

	# 1) наведение (и для своих, и для «чужих» отрисовок — дёшево)
	if _aimer != null:
		_aimer.step(delta)

	# 2) стрельба — только за живого локального бойца
	if vehicle == null or _is_vehicle_dead():
		return
	var want := _ext_fire or (_is_local_driver() and Input.is_action_pressed("fire"))
	if want:
		try_fire()


func try_fire() -> void:
	if _cool > 0.0 or not enabled:
		return
	if not _pay_cost():
		return
	_cool = fire_rate
	fire()


## Выстрел. Для PROJECTILE-типа возвращает снаряд (смоук-тесты следят за ним),
## для HITSCAN — null.
func fire() -> Node:
	var dir := aim_forward()
	dir = _spread(dir)
	var mz := _muzzle.global_position if _muzzle != null else global_position
	shots_fired += 1
	_idle_t = 0.0
	weapon_fired.emit(mz, dir)
	if _flash != null:
		_flash.visible = true
		_flash.scale = Vector3.ONE * randf_range(0.7, 1.3)
		_flash_t = 0.06

	if fire_type == FireType.PROJECTILE:
		return _spawn_projectile(mz, dir)
	_fire_hitscan(mz, dir)
	return null


# ════════════════════════ боеприпасы ════════════════════════

func _spawn_projectile(mz: Vector3, dir: Vector3) -> Node:
	var scene := projectile_scene
	if scene == null:
		scene = load("res://src/combat/projectile.tscn")
	var p = scene.instantiate()
	# хост — мир, не машина (снаряд живёт независимо от носителя)
	var host: Node = get_tree().root
	if vehicle != null and vehicle.get_parent() != null:
		host = vehicle.get_parent()
	host.add_child(p)
	if p.has_method("setup"):
		p.setup(mz, dir, projectile_speed, damage, projectile_lifetime, self, vehicle)
	return p


func _fire_hitscan(mz: Vector3, dir: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(mz, mz + dir * hitscan_range,
			ARENA_LAYER | VEHICLES_LAYER | HITBOX_LAYER)
	q.collide_with_areas = true  # «щедрые» хитбоксы доступны и хитскану
	if vehicle is PhysicsBody3D:
		q.exclude = [(vehicle as PhysicsBody3D).get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var collider: Object = hit.get("collider")
	var point: Vector3 = hit.get("position")
	_spawn_tracer(mz, point)
	_resolve_hit(collider, point)


## Общий разчёт попадания (используется и снарядом через register_hit).
func _resolve_hit(collider: Object, at: Vector3) -> void:
	var veh := _find_vehicle(collider)
	if veh == null:
		_spawn_impact_fx(at)  # только искры по геометрии
		return
	var health = veh.get_node_or_null("Health")
	if health == null:
		return
	health.take_damage(damage, _attacker_id())
	var is_kill: bool = health.is_dead
	hit_registered.emit(at, damage, is_kill)
	_spawn_impact_fx(at)


func register_projectile_hit(target_health, at: Vector3) -> void:
	## Мостик из Projectile: хитмаркер/счётчик — на оружии-источнике.
	var is_kill: bool = target_health != null and target_health.is_dead
	hit_registered.emit(at, damage, is_kill)


# ════════════════════════ ресурс ════════════════════════

func _pay_cost() -> bool:
	match resource_mode:
		ResourceMode.NONE:
			return true
		ResourceMode.BOOST_ENERGY:
			if vehicle != null and vehicle.has_method("get_boost_energy") \
					and vehicle.get_boost_energy() >= energy_cost:
				vehicle.add_boost(-energy_cost)
				return true
			return false
		ResourceMode.AMMO:
			if ammo >= 1.0:
				ammo -= 1.0
				return true
			return false
	return false


# ════════════════════════ вспомогательное ════════════════════════

func _ensure_structure() -> void:
	_turret = get_node_or_null(^"Turret") as Node3D
	if _turret == null:
		_turret = Node3D.new()
		_turret.name = "Turret"
		add_child(_turret)
	_barrel = _turret.get_node_or_null("Barrel") as Node3D
	if _barrel == null:
		_barrel = Node3D.new()
		_barrel.name = "Barrel"
		_turret.add_child(_barrel)
	_muzzle = _barrel.get_node_or_null("Muzzle") as Node3D
	if _muzzle == null:
		_muzzle = Marker3D.new()
		_muzzle.name = "Muzzle"
		_muzzle.position = Vector3(0.0, 0.0, -1.15)
		_barrel.add_child(_muzzle)
	# вспышка дула (placeholder SFX/VFX-хук)
	if _flash == null:
		_flash = MeshInstance3D.new()
		_flash.name = "MuzzleFlash"
		var sm := SphereMesh.new()
		sm.radius = 0.16
		sm.height = 0.32
		sm.radial_segments = 8
		sm.rings = 4
		_flash.mesh = sm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1.0, 0.75, 0.35)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.7, 0.3)
		m.emission_energy_multiplier = 3.0
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash.material_override = m
		_flash.visible = false
		_muzzle.add_child(_flash)


func _find_vehicle(node: Object) -> Node:
	## Collider -> машина: сам корпус (layer Vehicles) или хитбокс-область.
	if node == null:
		return null
	if node is Node3D and (node as Node).is_in_group("vehicles"):
		return node as Node
	if node is Area3D:
		var p := (node as Area3D).get_parent()
		if p != null and (p as Node).is_in_group("vehicles"):
			return p
	return null


func _is_vehicle_dead() -> bool:
	if vehicle == null:
		return false
	var h = vehicle.get_node_or_null("Health")
	return h != null and h.is_dead


func _is_local_driver() -> bool:
	## Input читаем только когда машина «наш пульт» (control_enabled):
	## у удалённых/ботовых экземпляров weapon молчит (стреляет сервер-логика).
	return vehicle != null and bool(vehicle.get("control_enabled"))


func _attacker_id() -> String:
	if vehicle != null:
		var idv: Variant = vehicle.get("unit_id")
		if idv != null and String(idv) != "":
			return String(idv)
		return String(vehicle.name)
	return "world"


## Казуальный разброс: равномерный конус spread_degrees вокруг направления.
func _spread(dir: Vector3) -> Vector3:
	if spread_degrees <= 0.0:
		return dir
	var ang := deg_to_rad(spread_degrees) * sqrt(randf())
	var ph := randf() * TAU
	var side := dir.cross(Vector3.UP)
	if absf(dir.y) > 0.92:
		side = dir.cross(Vector3.RIGHT)
	side = side.normalized()
	var up := dir.cross(side).normalized()
	var d := (dir + (side * cos(ph) + up * sin(ph)) * tan(ang)).normalized()
	return d


func _spawn_impact_fx(at: Vector3) -> void:
	var fx := preload("res://src/combat/impact_fx_placeholder.gd").new()
	fx.position = at  # локально: host — узел-мир в (0,0,0); до add_child
	var host: Node = get_tree().root
	if vehicle != null and vehicle.get_parent() != null:
		host = vehicle.get_parent()
	host.add_child(fx)


## Трассер хитскана: тонкий «стержень» на кадр (placeholder).
func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	if from.distance_squared_to(to) < 0.04:
		return
	var t := preload("res://src/combat/tracer_placeholder.gd").new()
	t.line_from = from
	t.line_to = to
	var host: Node = get_tree().root
	if vehicle != null and vehicle.get_parent() != null:
		host = vehicle.get_parent()
	host.add_child(t)


# ════════════════════════ Sprint 3: скелет нет-стейта ════════════════════════

func get_net_state() -> Dictionary:
	return {
		"y": _aimer.yaw if _aimer != null else 0.0,
		"p": _aimer.pitch if _aimer != null else 0.0,
		"c": _cool,
		"a": ammo,
		"s": shots_fired,
	}


func apply_net_state(s: Dictionary) -> void:
	# TODO Sprint 3: интерполяция наведения удалённых игроков
	if _aimer != null:
		if s.has("y"):
			_aimer.yaw = float(s["y"])
			_turret.rotation.y = _aimer.yaw
		if s.has("p"):
			_aimer.pitch = float(s["p"])
			_barrel.rotation.x = _aimer.pitch
