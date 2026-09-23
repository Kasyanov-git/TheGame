class_name DebugHud
extends Control
## Отладковый HUD Sprint 1+2: скорость, буст, HP/щит, хитмаркер, FPS, прицел.
## Вешается на Control-корень. На Sprint 4 заменяется полноценным UI
## гаража/меню через Platform Wrapper (Yandex/VK SDK).

@export var vehicle_path: NodePath = ^"../PlayerCar"

var _veh: ArcadeVehicle
@onready var _speed_label: Label = $SpeedLabel
@onready var _status_label: Label = $StatusLabel
@onready var _boost_bar: ProgressBar = $BoostBar
@onready var _fps_label: Label = $FpsLabel
@onready var _hp_bar: ProgressBar = $HealthBar
@onready var _hp_label: Label = $HealthLabel
@onready var _hit_label: Label = $HitLabel


func _ready() -> void:
	_veh = get_node_or_null(vehicle_path) as ArcadeVehicle
	if _veh == null:
		push_warning("DebugHud: машина не найдена по пути %s" % vehicle_path)
		return
	var h = _veh.get_health()
	if h != null:
		h.connect("health_changed", _on_health_changed)
	# хитмаркер: цепляемся за каждое оружие по мере монтирования
	_veh.connect("weapon_mounted", _on_weapon_mounted)
	for w in _veh.get_weapons():
		_hook_weapon(w)


func _process(delta: float) -> void:
	if _veh == null:
		return
	_speed_label.text = "%.0f км/ч" % _veh.speed_kmh
	_status_label.text = _status_text()
	_boost_bar.value = _veh.boost_ratio * 100.0
	_boost_bar.modulate = Color(0.35, 0.95, 1.0) if _veh.boost_ratio > 0.15 else Color(1.0, 0.45, 0.3)
	_fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
	if _hit_timer > 0.0:
		_hit_timer -= delta
		var a := clampf(_hit_timer / 0.55, 0.0, 1.0)
		_hit_label.modulate = Color(1.0, 1.0, 1.0, a)
		if _hit_timer <= 0.0:
			_hit_label.text = ""


var _hit_timer := 0.0


func _status_text() -> String:
	var parts := PackedStringArray()
	parts.append("AIR" if not _veh.grounded else ("WALL-RIDE" if _veh.is_on_wall else "GROUND"))
	if _veh.boost_active:
		parts.append("BOOST")
	if _veh.is_drifting:
		parts.append("DRIFT")
	var h = _veh.get_health()
	if h != null:
		if h.is_dead:
			parts.append("DESTROYED")
		elif h.shield_time_left > 0.0:
			parts.append("SHIELD %.1fs" % h.shield_time_left)
	var nm := get_node_or_null("/root/NetworkManager")
	if nm != null and nm.get("active"):
		var snap: Dictionary = nm.call("snapshot")
		parts.append("NET %s · %s · ⏱%.0fs" % [
			String(nm.get("status_line")),
			String(snap.get("ms", "?")),
			float(snap.get("gt", 0.0)),
		])
	return "  ·  ".join(parts)


func _on_health_changed(new_hp: float, max_hp: float) -> void:
	_hp_bar.value = clampf(new_hp / maxf(max_hp, 1.0), 0.0, 1.0) * 100.0
	_hp_label.text = "HP %d / %d" % [int(new_hp), int(max_hp)]
	if new_hp <= 0.0:
		_hp_bar.modulate = Color(0.8, 0.2, 0.16)
	elif new_hp < 0.4 * max_hp:
		_hp_bar.modulate = Color(1.0, 0.55, 0.25)
	else:
		_hp_bar.modulate = Color(0.42, 0.95, 0.45)


func _on_weapon_mounted(weapon: Node) -> void:
	_hook_weapon(weapon)


func _hook_weapon(weapon: Node) -> void:
	if weapon == null:
		return
	weapon.connect("hit_registered", _on_hit_registered)


func _on_hit_registered(_target_position: Vector3, dmg: float, is_kill: bool) -> void:
	_hit_label.text = "✕  -%d" % int(dmg) + ("   ELIMINATED!" if is_kill else "")
	_hit_label.add_theme_color_override("font_color",
			Color(1.0, 0.35, 0.3) if is_kill else Color(1.0, 0.87, 0.4))
	_hit_timer = 0.55
