extends Node3D
## NetAvatar — марионетка ЧУЖОЙ сетевой машины (Sprint 3, ТЗ п.2: Entity
## Interpolation). Позиция — lerp между двумя снапшотами, поворот — slerp
## кватернионов; рендерим на INTERP_DELAY (100 мс) в прошлом — снапшоты 20 Гц
## ложатся в плавное движение без рывков. Физики/коллизий нет: child-машина с
## control_enabled=false, freeze, collision off.
##
## Ключевое имя класса не объявляем (class_name): wasm-сборка не резолвит
## class_name в рантайм-вызовах (урок Sprint 2) — создаём через preload().new().

const INTERP_DELAY := 0.10        ## ТЗ: ~100 мс интерполяционный буфер

var sid: String = ""
var vehicle = null                 # ArcadeVehicle внутри (duck-typed)
var _keys: Array = []              # [{t, pos, yaw, aim_yaw, pitch, hp}]
var _aim_gizmo: MeshInstance3D = null

# сглаживание «телепорт-коррекций» сервера (soft align): если сервер и клиент
# разъехались сильно, прыжок в буфере не должен дёргать картинку
var _align_t := 0.0


func setup(p_sid: String, show_gizmo: bool = true) -> void:
	sid = p_sid
	if show_gizmo and _aim_gizmo == null:
		_aim_gizmo = MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.14, 0.14, 2.4)
		_aim_gizmo.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.35, 0.2)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.35, 0.2)
		mat.emission_energy_multiplier = 1.6
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_aim_gizmo.material_override = mat
		_aim_gizmo.position = Vector3(0.0, 0.95, -1.4)
		add_child(_aim_gizmo)


## Вызывается на каждый снапшот, где есть этот игрок. t = локальное время
## приёма (дрожание сети съедается буфером, а не серверными отметками).
func push_key(pos: Vector3, yaw: float, aim_yaw: float, pitch: float, hp: float) -> void:
	_keys.append({
		"t": Time.get_ticks_msec() / 1000.0,
		"pos": pos, "yaw": yaw, "aim_yaw": aim_yaw, "pitch": pitch, "hp": hp,
	})
	while _keys.size() > 20:
		_keys.pop_front()


func _physics_process(delta: float) -> void:
	_align_t = maxf(0.0, _align_t - delta)
	if _keys.size() < 2:
		return
	var render_t: float = float(_keys.back()["t"]) - INTERP_DELAY
	var a: Dictionary = _keys[0]
	var b: Dictionary = _keys[1]
	for i in range(_keys.size() - 1):
		if float(_keys[i]["t"]) <= render_t and float(_keys[i + 1]["t"]) >= render_t:
			a = _keys[i]
			b = _keys[i + 1]
			break
		if float(_keys[i]["t"]) < render_t:
			a = _keys[i]
			b = _keys[i + 1]
	var span: float = float(b["t"]) - float(a["t"])
	var alpha: float = 0.5
	if span > 0.0001:
		alpha = clampf((render_t - float(a["t"])) / span, 0.0, 1.0)
	var pa: Vector3 = a["pos"]
	var pb: Vector3 = b["pos"]
	global_position = pa.lerp(pb, alpha)
	var qa := Quaternion(Vector3.UP, float(a["yaw"]))
	var qb := Quaternion(Vector3.UP, float(b["yaw"]))
	global_transform.basis = Basis(qa.slerp(qb, alpha))
	if _aim_gizmo != null:
		var ay: float = float(a["aim_yaw"])
		var by: float = float(b["aim_yaw"])
		var yaw_local: float = lerpf_angle(ay, by, alpha) - _lerp_yaw(a, b, alpha)
		_aim_gizmo.rotation.y = yaw_local
	# HP — серверный факт напрямую в HealthComponent (net-режим: только сет)
	var hnode = vehicle.get_node_or_null("Health") if vehicle != null else null
	if hnode != null:
		hnode.call("set_net_hp", float(b["hp"]))


func _lerp_yaw(a: Dictionary, b: Dictionary, alpha: float) -> float:
	return lerpf_angle(float(a["yaw"]), float(b["yaw"]), alpha)


static func lerpf_angle(a: float, bb: float, w: float) -> float:
	var d: float = fmod(bb - a + PI, TAU)
	if d < 0.0:
		d += TAU
	return a + (d - PI) * w
