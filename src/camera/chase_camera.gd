class_name ChaseCameraRig
extends Node3D
## Динамическая камера преследования (Sprint 1, п.3 ТЗ).
##
## Структура: этот риг (сглаженно катится за машиной) -> SpringArm3D
## (плечо 6.0 м, наклон -15°, ретракт при окклюзии ареной) -> Camera3D.
##
## Ключевые решения:
##   * ВСЁ сглаживание в _process() на ИНТЕРПОЛИРОВАННОМ transform машины
##     (physics_interpolate у RigidBody) — поэтому нет дерганья physical
##     шага (DoD 3). SpringArm3D обновляется на физ. тике, но креша-смещение
##     наследуется от рига, который двигается покадрово — кадр за кадром
##     позиция камеры непрерывна.
##   * lerp-скорость 0.12 на кадр 60fps, пересчитанная через delta
##     (1 - (1-k)^(dt*60)) — одинаковое «ощущение» на 60/120/144 Гц, что
##     критично для будущего web-экспорта (там dt плавает).
##   * heading = смесь курса машины и вектора скорости: в дрифте камера
##     смотрит «в поворот», как в Rocket League.
##   * Look-ahead: фокус смещается вдоль направления движения на k*скорость.
##   * FOV 75° -> 90° (скорость+буст) — эффект ускорения без post-processing,
##     дёшево для WebGL2 (ТЗ: low-poly + шейдерный стиль).

@export var vehicle: NodePath
@export var arm_path: NodePath = ^"SpringArm3D"
@export var camera_path: NodePath = ^"SpringArm3D/Camera3D"

@export_group("Follow")
@export var follow_smooth := 0.12          ## ТЗ: 0.12 на кадр @60fps
@export var yaw_smooth := 0.14             ## сглаживание разворота рига
@export var heading_velocity_weight := 0.55  ## доля вектора скорости в heading (дрифт-камера)
@export var pivot_height := 1.25           ## м — точка, за которой «тянется» риг
@export var lookahead_speed := 5.0         ## м смещения фокуса на max_speed (ТЗ: look-ahead)

@export_group("Arm")
@export var arm_length := 6.0              ## ТЗ: 6.0 м
@export var arm_pitch_deg := -15.0         ## ТЗ: -15°
@export var arm_length_per_speed := 0.055  ## удлинение плеча на (м/с): +2.5м на 45
@export var arm_pitch_speed_bias := -5.0   ## на скорости чуть сильнее смотрим вниз

@export_group("FOV")
@export var fov_base := 75.0               ## ТЗ: 75°
@export var fov_boost := 90.0              ## ТЗ: 90° на бусте
@export var fov_speed_bias := 0.4          ## доля «скоростного» FOV (остальное — факт. буст)
@export var fov_smooth := 6.0              ## 1/с

@export var max_ref_speed := 45.0          ## м/с для нормировки (обычно max_speed машины)

var _veh: ArcadeVehicle
var _arm: SpringArm3D
var _cam: Camera3D
var _rig_yaw := 0.0
var _snapped := false


func _ready() -> void:
	_veh = get_node_or_null(vehicle) as ArcadeVehicle
	_arm = get_node_or_null(arm_path) as SpringArm3D
	_cam = get_node_or_null(camera_path) as Camera3D
	if _veh == null or _cam == null:
		push_warning("ChaseCameraRig: не заданы vehicle/camera — камера стоит")


## Первый кадр — телепорт рига за машину (без «подлёта» из начала координат).
func _snap_to_vehicle() -> void:
	if _veh == null:
		return
	global_position = _veh.global_position + Vector3(0.0, pivot_height, 0.0) \
		+ (-_veh.global_transform.basis.z) * -arm_length
	var f := -_veh.global_transform.basis.z
	_rig_yaw = atan2(-f.x, -f.z)
	rotation = Vector3(0.0, _rig_yaw, 0.0)


func _process(delta: float) -> void:
	if _veh == null:
		return
	if _cam == null:
		_cam = get_node_or_null(camera_path) as Camera3D
	if not _snapped:
		_snapped = true
		_snap_to_vehicle()

	# ── желаемое состояние ──
	var v := _veh.linear_velocity
	var speed := v.length()
	var speed_ratio := clampf(speed / max_ref_speed, 0.0, 1.5)
	var up := _veh.ground_normal if _veh.grounded else Vector3.UP

	# heading: курс машины + подмешиваем вектор скорости (заглядываем в занос)
	var car_fwd := -_veh.global_transform.basis.z
	var vel_dir := Vector3(v.x, 0.0, v.z)
	vel_dir = vel_dir.normalized() if vel_dir.length_squared() > 0.01 else car_fwd
	var car_fwd_flat := Vector3(car_fwd.x, 0.0, car_fwd.z)
	car_fwd_flat = car_fwd_flat.normalized() if car_fwd_flat.length_squared() > 1e-6 else Vector3(0.0, 0.0, -1.0)
	var blend_w := clampf(heading_velocity_weight * speed_ratio, 0.0, 0.85)
	var heading := car_fwd_flat.lerp(vel_dir, blend_w).normalized()

	var want_pos := _veh.global_position + up * pivot_height + heading * lookahead_speed * speed_ratio

	# framerate-независимый эквивалент «lerp с коэффициентом k на кадр 60fps»
	var pos_t := 1.0 - pow(1.0 - follow_smooth, delta * 60.0)
	global_position = global_position.lerp(want_pos, pos_t)

	# ── ориентация рига: только yaw, камера держим горизонтальной ──
	var want_yaw := atan2(-heading.x, -heading.z)
	var yaw_t := 1.0 - pow(1.0 - yaw_smooth, delta * 60.0)
	_rig_yaw = lerp_angle(_rig_yaw, want_yaw, yaw_t)
	rotation = Vector3(0.0, _rig_yaw, 0.0)

	# ── SpringArm: динамическое плечо/наклон (окклюзию ареной считает сам) ──
	if _arm:
		_arm.spring_length = arm_length + speed * arm_length_per_speed
		# на скорости смотрим чуть сильнее вниз: мягкий «присед» обзора
		_arm.rotation.x = deg_to_rad(arm_pitch_deg + speed_ratio * arm_pitch_speed_bias)

	# ── динамический FOV ──
	var fov_w := clampf(maxf(speed_ratio * fov_speed_bias, 1.0 if _veh.boost_active else 0.0), 0.0, 1.0)
	if _veh.is_drifting:
		fov_w = maxf(fov_w, 0.35)
	var want_fov := lerpf(fov_base, fov_boost, fov_w)
	_cam.fov = lerpf(_cam.fov, want_fov, clampf(fov_smooth * delta, 0.0, 1.0))
