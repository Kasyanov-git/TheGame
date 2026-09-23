class_name ExplosionPlaceholder
extends Node3D
## Заглушка взрыва destroyed-машины (п.3 ТЗ: «Placeholder Particle / Force Push
## на обломки»). Разлет-обломков и партиклы — Sprint 4; физический выхлоп
## (выталкивание соседних машин) реализован по-настоящему: аркаду приятно
## «сдувает» с точки смерти, и это бесплатно для веба.

@export var radius := 7.5               ## м, зона выталкивания
@export var push_speed := 11.0          ## м/с — приращение скорости соседям
@export var duration := 0.7             ## с, жизнь вспышки
@export var core_color := Color(1.0, 0.55, 0.18)
@export var ring_color := Color(1.0, 0.82, 0.35)

var exclude_bodies: Array[RID] = []

var _t := 0.0
var _core_mat: StandardMaterial3D
var _ring_mat: StandardMaterial3D


func _ready() -> void:
	add_to_group("explosions")
	_build_visual()
	_push_bodies()


func _build_visual() -> void:
	# ядро-огонь
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 12
	sm.rings = 6
	core.mesh = sm
	_core_mat = StandardMaterial3D.new()
	_core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_core_mat.albedo_color = Color(core_color.r, core_color.g, core_color.b, 0.95)
	_core_mat.emission_enabled = true
	_core_mat.emission = core_color
	_core_mat.emission_energy_multiplier = 4.0
	core.material_override = _core_mat
	add_child(core)
	# ударное кольцо (тор, раскрывается в стороны)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 1.15
	tm.rings = 12
	tm.ring_segments = 20
	ring.mesh = tm
	ring.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.albedo_color = Color(ring_color.r, ring_color.g, ring_color.b, 0.8)
	_ring_mat.emission_enabled = true
	_ring_mat.emission = ring_color
	_ring_mat.emission_energy_multiplier = 2.0
	ring.material_override = _ring_mat
	add_child(ring)


## Force push: все машины в радиусе получают импульс «от взрыва» + подброс.
func _push_bodies() -> void:
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var shp := SphereShape3D.new()
	shp.radius = radius
	q.shape = shp
	var tr := Transform3D()
	tr.origin = global_position
	q.transform = tr
	q.collision_mask = 2  # Vehicles
	q.collide_with_bodies = true
	q.collide_with_areas = false
	q.exclude = exclude_bodies
	for res in space.intersect_shape(q, 16):
		var b: Object = res.get("collider")
		if b is RigidBody3D and not (b as RigidBody3D).freeze:
			var rb := b as RigidBody3D
			var dir := rb.global_position - global_position
			dir.y = maxf(dir.y, 0.7)  # «сдувает с землицы» — аркадно
			dir = dir.normalized()
			rb.linear_velocity += dir * push_speed


func _process(delta: float) -> void:
	_t += delta
	var k := clampf(_t / maxf(duration, 0.01), 0.0, 1.0)
	scale = Vector3.ONE * lerpf(0.45, 2.9, k)
	if _core_mat:
		var c := _core_mat.albedo_color
		c.a = 0.95 * (1.0 - k)
		_core_mat.albedo_color = c
	if _ring_mat:
		var r := _ring_mat.albedo_color
		r.a = 0.8 * (1.0 - k) * (1.0 - k)
		_ring_mat.albedo_color = r
	if _t >= duration:
		queue_free()
