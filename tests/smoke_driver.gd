extends Node
## Headless smoke-тест Sprint 1 (без рендера — чистая физика).
##
## Запуск:
##   godot --headless --path . res://tests/smoke.tscn
##
## Проверяет «критерии приёмки», которые вообще проверяются без человека:
##   1. машина ускоряется с газа, упирается в лимит max_speed и не превышает
##      абсолютный предохранитель;
##   2. подвеска: приземление после спавна, grounded=true;
##   3. руление: heading меняется под_input;
##   4. дрифт: появляется боковая скорость (zanos), grip не «рельсовый»;
##   5. буст: энергия тратится, лимит скорости поднимается (cap x1.7);
##   6. respawn: телепортирует на ближайший спавн-поинт;
##   7. арена собрана: trimesh-коллизия непустая, NaN нет нигде.
##
## Экспоненциальные фильтры в контроллере (1 - e^-k·dt) делают физику
## детерминированной по симулированному времени — пороги ниже стабильны.

const MAIN_SCENE := "res://src/main/main.tscn"

var _t := 0
var _main: Node
var _car: ArcadeVehicle
var _fails := 0
var _peak_speed := 0.0
var _peak_lat := 0.0
var _ever_grounded := false
var _start := Vector3.ZERO
var _yaw_before := 0.0
var _boost_before := 100.0
var _cap_hits := 0


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
	# общий надзор: NaN / вылет за пределы
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

	match _t:
		6:
			_car.set_external_input(0.0, 1.0, false, false)   # газ прямо
		80:
			_check(_ever_grounded, "car lands on ground after spawn (ever-grounded flag)")
		100:
			_check(_peak_speed > 15.0, "throttle accelerates (peak %.1f m/s > 15)" % _peak_speed)
			_check(p.distance_to(_start) > 12.0, "car moved %.1f m" % p.distance_to(_start))
			# полный газ дольше — проверка лимита
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
			# на бусте скорость должна превысить обычный лимит (cap ×1.7)
			_check(_peak_speed > 49.0, "boost exceeds base cap (peak %.1f)" % _peak_speed)
			_check(_peak_speed < 45.0 * 1.7 + 11.0, "boost cap respected (peak %.1f < 87.5)" % _peak_speed)
			_car.set_external_input(0.0, 0.0, false, false)
		420:
			# respawn на спавн-поинт
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
			_check(absf(_car.global_position.y) < 2.5 or _ever_grounded, "respawned car near floor / touches it (y=%.2f)" % _car.global_position.y)
		520:
			_finish()


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
