class_name DebugHud
extends Control
## Отладковый HUD Sprint 1: скорость, буст, состояние контакта, FPS.
## Вешается на Control-корень. На Sprint 4 заменяется полноценным UI
## гаража/меню через Platform Wrapper (Yandex/VK SDK).

@export var vehicle_path: NodePath = ^"../PlayerCar"

var _veh: ArcadeVehicle
@onready var _speed_label: Label = $SpeedLabel
@onready var _status_label: Label = $StatusLabel
@onready var _boost_bar: ProgressBar = $BoostBar
@onready var _fps_label: Label = $FpsLabel


func _ready() -> void:
	_veh = get_node_or_null(vehicle_path) as ArcadeVehicle
	if _veh == null:
		push_warning("DebugHud: машина не найдена по пути %s" % vehicle_path)


func _process(_delta: float) -> void:
	if _veh == null:
		return
	_speed_label.text = "%.0f км/ч" % _veh.speed_kmh
	_status_label.text = _status_text()
	_boost_bar.value = _veh.boost_ratio * 100.0
	_boost_bar.modulate = Color(0.35, 0.95, 1.0) if _veh.boost_ratio > 0.15 else Color(1.0, 0.45, 0.3)
	_fps_label.text = "FPS: %d" % Engine.get_frames_per_second()


func _status_text() -> String:
	var parts := PackedStringArray()
	parts.append("AIR" if not _veh.grounded else ("WALL-RIDE" if _veh.is_on_wall else "GROUND"))
	if _veh.boost_active:
		parts.append("BOOST")
	if _veh.is_drifting:
		parts.append("DRIFT")
	return "  ·  ".join(parts)
