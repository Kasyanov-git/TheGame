class_name TurretAimer
extends Node
## Автонаведение турели в точку прицела (Sprint 2, п.1 ТЗ).
##
## Управление двумя пивотами оружия (их создаёт BaseWeapon):
##   YawPivot   — поворот вокруг локальной Y сокета (ограничен только питчем орудия);
##   PitchPivot — тангаж вокруг локальной X, кламп -10°…+30° (ТЗ — «предотвращение
##                неестественных выворотов»).
##
## Точка прицеливания — Camera Raycast из центра экрана в 3D-мир (ТЗ): куда
## смотрит прицел, туда и наводятся. Если рядом с точкой луча (< snap_radius)
## есть чужой хитбокс — «aim assist» цепляет его центр (аркадный стандарт:
## на веб-платформах прицел без мыши должен быть играбельным).
##
## Скорость поворота ограничена (ТЗ: turret_rotation_speed = 12.0 рад/с) —
## наведение НЕ мгновенное, есть ощущение массы орудия; боеприпас летит
## по ФАКТИЧЕСкому направлению ствола, поэтому на упреждение реально влияют
## инерция наводки и курс машины.
##
## Детерминизм: никаких RayCast3D-нод — прямые запросы space (урок Sprint 1:
## одинаково на GodotPhysics3D/Jolt, сервер Colyseus сможет повторить логику).

const ARENA_LAYER := 1
const VEHICLES_LAYER := 2
const HITBOX_LAYER := 8  ## «большие» триггеры машин (Area3D, слой Hitboxes=bit4)

@export var rotation_speed := 12.0         ## ТЗ: рад/с — потолок скорости башни
@export var min_pitch_deg := -10.0         ## ТЗ: −10°
@export var max_pitch_deg := 30.0          ## ТЗ: +30°
@export var aim_range := 220.0             ## м, длина луча прицела при промахе
@export var snap_radius := 12.0            ## м, радиус aim-assist вокруг точки луча
@export var align_tolerance_deg := 3.0     ## порог «ствол наведён»

## Публичное состояние (для HUD/стрельбы)
var yaw := 0.0                             ## текущий локальный yaw пивота
var pitch := 0.0                           ## текущий питч (положительный = вверх)
var aligned := false
var aim_point := Vector3.ZERO              ## куда наводимся (мир)
var target_kind := "none"                  ## "geometry" | "vehicle" | "range"

var _pivot_yaw: Node3D = null
var _pivot_pitch: Node3D = null
var _muzzle: Node3D = null
var _anchor: Node3D = null                 ## машина-носитель (исключения лучей)


## Вызывается из BaseWeapon._physics_process (один шаг за физ. тик —
## детерминированный порядок: сначала наведение, потом выстрел).
func step(delta: float) -> void:
	if _pivot_yaw == null or _pivot_pitch == null:
		return
	var base := _anchor if _anchor != null else (_pivot_yaw.get_parent() as Node3D)
	if base == null:
		return
	aim_point = _crosshair_point(base)

	# ── aim assist: цепляем ближайший живой хитбокс вокруг точки прицела ──
	target_kind = "geometry"
	var snapped := _snap_target(aim_point)
	if snapped != null:
		aim_point = snapped.global_position
		target_kind = "vehicle"

	# ── целевые углы в локальном пространстве сокета ──
	var muzzle_pos := base.global_position
	if _muzzle != null:
		muzzle_pos = _muzzle.global_position
	var to_target := aim_point - muzzle_pos
	if to_target.length_squared() < 1e-6:
		return
	# переносим направление в систему координат сокета (без учёта текущих
	# yaw/pitch турели — пивоты крутятся ОТНОСИТЕЛЬНО него)
	var inv := base.global_transform.affine_inverse()
	var v := inv.basis * to_target.normalized()  # Basis*Vector3 (4.7: xform удалён)
	var des_yaw := atan2(-v.x, -v.z)
	var des_pitch := atan2(v.y, maxf(Vector2(v.x, v.z).length(), 0.001))
	var pitch_min := deg_to_rad(min_pitch_deg)
	var pitch_max := deg_to_rad(max_pitch_deg)
	des_pitch = clampf(des_pitch, pitch_min, pitch_max)

	# ── движение с ограниченной скоростью (ощущение веса орудия) ──
	var max_step := rotation_speed * delta
	var err_yaw := wrapf(des_yaw - yaw, -PI, PI)
	yaw = wrapf(yaw + clampf(err_yaw, -max_step, max_step), -PI, PI)
	pitch = clampf(pitch + clampf(des_pitch - pitch, -max_step, max_step), pitch_min, pitch_max)

	_pivot_yaw.rotation.y = yaw
	_pivot_pitch.rotation.x = pitch

	var tol := deg_to_rad(align_tolerance_deg)
	aligned = absf(wrapf(des_yaw - yaw, -PI, PI)) < tol and absf(des_pitch - pitch) < tol


## Мировое направление ствола (КУДА реально полетит снаряд).
func get_forward() -> Vector3:
	if _muzzle != null:
		return -_muzzle.global_transform.basis.z
	if _pivot_pitch != null:
		return -_pivot_pitch.global_transform.basis.z
	if _anchor != null:
		return -_anchor.global_transform.basis.z
	return Vector3.BACK


func configure(pivot_yaw: Node3D, pivot_pitch: Node3D, muzzle: Node3D, anchor: Node3D) -> void:
	_pivot_yaw = pivot_yaw
	_pivot_pitch = pivot_pitch
	_muzzle = muzzle
	_anchor = anchor


# ════════════════════════ внутреннее ════════════════════════

## Точка, куда указывает прицел: луч камеры из центра экрана.
func _crosshair_point(base: Node3D) -> Vector3:
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp != null else null
	var origin: Vector3
	var dir: Vector3
	var cast_range := aim_range
	var size := vp.get_visible_rect().size if vp != null else Vector2.ZERO
	if cam != null and size.y > 1.0:
		var center := size * 0.5
		origin = cam.project_ray_origin(center)
		dir = cam.project_ray_normal(center)
	# Вырожденный ray (headless/CI: viewport без высоты → project_ray_* == ZERO;
	# камера ещё не в дереве) — фолбэк «целься курсом машины» в 24 м, чтобы
	# aim-assist доставал до тестовой цели. В браузере size валиден всегда.
	if dir.length_squared() < 1e-6:
		origin = base.global_position + Vector3.UP * 1.2
		dir = -base.global_transform.basis.z
		dir.y = 0.0
		dir = dir.normalized() if dir.length_squared() > 1e-9 else Vector3.BACK
		cast_range = minf(aim_range, 24.0)
	var want := origin + dir * cast_range
	if _anchor == null:
		return want
	var space := _anchor.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, want, ARENA_LAYER | VEHICLES_LAYER)
	q.collide_with_areas = false
	if _anchor is PhysicsBody3D:
		q.exclude = [(_anchor as PhysicsBody3D).get_rid()]  # не целимся в себя
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		target_kind = "geometry"
		return hit["position"]
	return want


## Ближайший к точке прицела чужой живой хитбокс в радиусе snap_radius, либо null.
func _snap_target(point: Vector3) -> Node3D:
	if snap_radius <= 0.0 or _anchor == null:
		return null
	var space := _anchor.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var shp := BoxShape3D.new()
	var r := snap_radius
	shp.size = Vector3(r * 2.0, maxf(r, 4.0), r * 2.0)
	q.shape = shp
	var tr := Transform3D()
	tr.origin = point
	q.transform = tr
	q.collision_mask = HITBOX_LAYER
	q.collide_with_areas = true
	q.collide_with_bodies = false
	var best: Area3D = null
	var best_d := snap_radius * snap_radius
	for res in space.intersect_shape(q, 8):
		var area: Object = res.get("collider")
		var hb := area as Area3D
		if hb == null:
			continue
		var owner3d := hb.get_parent() as Node3D
		if owner3d == null or owner3d == _anchor:
			continue  # свои — не цель
		var h = owner3d.get_node_or_null("Health")
		if h != null and h.is_dead:
			continue  # трупы не подсвечиваем
		var d := hb.global_position.distance_squared_to(point)
		if d < best_d:
			best_d = d
			best = hb  # возвращаем сам хитбокс — его центр = точка наводки
	return best
