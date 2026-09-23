class_name Projectile
extends Area3D
## «Arcade Fast Projectile» (Sprint 2, п.2 ТЗ — основной тип снаряда).
##
## Формула по ТЗ: скорость 120 м/с, щедрый сферический триггер (радиус 0.9 м —
## «по быстрым машинам легко попадать»), автоуничтожение через lifetime 3.0 с
## или при попадании в геометрию/игрока.
##
## Реализация — Area3D (нода-носитель по ТЗ) + ручная кинематика вместо
## RigidBody3D-полёта:
##   * никакой гравитации/отскоков — «чистый луч» до точки, как в RL/WoT-аркадах;
##   * детерминизм: сервер Sprint 3 повторит шаг теми же запросами space;
##   * анти-туннелирование: sweep-луч prev→next против геометрии (стены —
##     односторонний тримеш, шаг 2 м легко проскакивает «на глазок»),
##     и simultaneous sphere-запрос по хитбоксам машин (щедрость 0.9 м).
## Попадание по машине: ищем HealthComponent → take_damage(damage, attacker_id).
## signal impacted — ВФХ/звук-хук; hit_registered отдаётся на оружии-источнике.

signal impacted(position_world: Vector3, hit_vehicle: bool, is_kill: bool)
signal expired

const ARENA_LAYER := 1
const VEHICLES_LAYER := 2
const HITBOX_LAYER := 8

@export var speed := 120.0                 ## ТЗ: 120 м/с
@export var damage := 15.0
@export var lifetime := 3.0                ## ТЗ: 3.0 с
@export var trigger_radius := 0.9          ## ТЗ: 0.8–1.0 м

var is_active := false
var source = null                          ## BaseWeapon-источник (Variant: тип не нужен)
var owner_vehicle: Node = null             ## не попадания по себе

var _vel := Vector3.ZERO
var _t := 0.0


func _ready() -> void:
	add_to_group("projectiles")
	# физ-серверArea не толкает никого: вся детекция — прямые запросы ниже
	collision_layer = 0
	collision_mask = 0
	monitoring = false


## Вызывается из BaseWeapon сразу после instantiate+add_child.
func setup(origin: Vector3, dir: Vector3, p_speed: float, p_damage: float,
		p_lifetime: float, p_source: Node = null, p_owner: Node = null) -> void:
	global_position = origin
	speed = p_speed
	damage = p_damage
	lifetime = p_lifetime
	source = p_source
	owner_vehicle = p_owner
	_vel = dir.normalized() * speed
	is_active = true


func _physics_process(delta: float) -> void:
	if not is_active:
		return
	_t += delta
	if _t >= lifetime:
		_despawn_expired()
		return
	var from := global_position
	var to := from + _vel * delta

	# 1) геометрия/корпуса: sweep-луч по пройденному сегменту
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to, ARENA_LAYER | VEHICLES_LAYER)
	q.collide_with_areas = false
	if owner_vehicle is PhysicsBody3D:
		q.exclude = [(owner_vehicle as PhysicsBody3D).get_rid()]
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		var collider: Object = hit.get("collider")
		var point: Vector3 = hit.get("position")
		var veh := _find_vehicle(collider)
		if veh != null:
			_hit_vehicle(veh, point)
		else:
			_impact(point, false, false)
		return

	global_position = to

	# 2) «щедрость»: сфера 0.9 м по хитбоксам машин (Area3D, слой 4)
	var sq := PhysicsShapeQueryParameters3D.new()
	var shp := SphereShape3D.new()
	shp.radius = trigger_radius
	sq.shape = shp
	var tr := Transform3D()
	tr.origin = to
	sq.transform = tr
	sq.collision_mask = HITBOX_LAYER
	sq.collide_with_areas = true
	sq.collide_with_bodies = false
	for res in space.intersect_shape(sq, 4):
		var area: Object = res.get("collider")
		if not (area is Area3D):
			continue
		var veh2 := _find_vehicle(area)
		if veh2 == null or veh2 == owner_vehicle:
			continue
		_hit_vehicle(veh2, to)
		return


# ════════════════════════ разрешение попадания ════════════════════════

func _hit_vehicle(veh: Node, at: Vector3) -> void:
	var health = veh.get_node_or_null("Health")
	var is_kill := false
	if health != null:
		health.take_damage(damage, _attacker_id())
		is_kill = health.is_dead
		if source != null and source.has_method("register_projectile_hit"):
			source.register_projectile_hit(health, at)
	_impact(at, true, is_kill)


func _impact(at: Vector3, hit_vehicle: bool, is_kill: bool) -> void:
	is_active = false
	var fx := preload("res://src/combat/impact_fx_placeholder.gd").new()
	fx.position = at  # локально: глобальные сеттеры вне дерева запрещены
	if hit_vehicle:
		fx.flash_color = Color(1.0, 0.45, 0.25)
	var host := get_parent()
	if host == null:
		host = get_tree().root
	host.add_child(fx)  # под мир, не под снаряд (снаряд сейчас освободится)
	impacted.emit(at, hit_vehicle, is_kill)
	queue_free()


func _despawn_expired() -> void:
	is_active = false
	expired.emit()
	queue_free()


func _find_vehicle(node: Object) -> Node:
	if node == null:
		return null
	if node is Node and (node as Node).is_in_group("vehicles"):
		return node
	if node is Area3D:
		var p := (node as Area3D).get_parent()
		if p != null and (p as Node).is_in_group("vehicles"):
			return p
	return null


func _attacker_id() -> String:
	if owner_vehicle != null:
		var idv: Variant = owner_vehicle.get("unit_id")
		if idv != null and String(idv) != "":
			return String(idv)
		return String(owner_vehicle.name)
	return "world"
