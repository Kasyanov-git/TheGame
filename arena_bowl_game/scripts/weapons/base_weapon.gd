class_name BaseWeapon
extends Node3D

## Base Weapon Component - Abstract class for all weapons
## Sprint 2: Combat & Perks

# Signals
signal weapon_fired(muzzle_position: Vector3, direction: Vector3)
signal weapon_reloaded()

# Configuration
@export_group("Weapon Stats")
@export var fire_rate: float = 0.15  # Seconds between shots
@export var damage: float = 15.0
@export var energy_cost: float = 10.0
@export var spread_degrees: float = 1.5
@export var max_ammo: int = -1  # -1 = infinite ammo
@export var reload_time: float = 2.0

@export_group("Turret Aiming")
@export var turret_rotation_speed: float = 12.0  # rad/s
@export var pitch_min: float = -10.0  # degrees
@export var pitch_max: float = 30.0  # degrees

@export_group("References")
@export var muzzle_offset: Vector3 = Vector3(0, 0.5, 1.5)
@export var gun_mount_point: Node3D

# State
var current_ammo: int
var _fire_cooldown: float = 0.0
var _reload_timer: float = 0.0
var _is_reloading: bool = false
var _current_pitch: float = 0.0
var _current_yaw: float = 0.0
var _target_pitch: float = 0.0
var _target_yaw: float = 0.0

# References
var _owner_vehicle: Node3D
var _camera: Camera3D

func _ready() -> void:
	current_ammo = max_ammo if max_ammo > 0 else -1
	_owner_vehicle = get_parent()
	
	# Find camera in scene
	var game_manager = get_tree().get_first_node_in_group("game_manager")
	if game_manager and game_manager.has_node("MainCamera"):
		_camera = game_manager.get_node("MainCamera")
	else:
		# Try to find any camera in the scene
		_camera = _find_camera_in_scene()

func _find_camera_in_scene() -> Camera3D:
	for node in get_tree().get_nodes_in_group("player_camera"):
		if node is Camera3D:
			return node
	
	# Fallback: find first camera in scene
	var cameras = []
	get_tree().get_nodes_in_group("cameras").append_array(cameras)
	if cameras.size() > 0:
		return cameras[0] as Camera3D
	
	# Last resort: search all nodes
	for n in get_tree().get_current_scene().get_children():
		if n is Camera3D:
			return n
	return null

func _process(delta: float) -> void:
	if _fire_cooldown > 0:
		_fire_cooldown -= delta
	
	if _is_reloading:
		_reload_timer -= delta
		if _reload_timer <= 0:
			_finish_reload()
	
	# Update turret aiming if we have a target
	if not _is_reloading and can_fire():
		_update_turret_aiming(delta)

func _update_turret_aiming(delta: float) -> void:
	if not _camera:
		return
	
	# Get aim target from camera raycast
	var viewport = get_viewport()
	if not viewport:
		return
	
	var mouse_pos = viewport.get_mouse_position()
	var from = _camera.project_ray_origin(mouse_pos)
	var to = from + _camera.project_ray_normal(mouse_pos) * 1000.0
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [_owner_vehicle] if _owner_vehicle else []
	
	var result = space_state.intersect_ray(query)
	var target_pos = result.position if result else to
	
	# Calculate direction from weapon to target
	var weapon_pos = global_position + muzzle_offset
	var direction = (target_pos - weapon_pos).normalized()
	
	# Convert to local rotation
	var look_at_target = look_at_direction(direction)
	var target_euler = look_at_target
	
	# Clamp pitch
	var target_pitch_rad = deg_to_rad(pitch_min)
	var max_pitch_rad = deg_to_rad(pitch_max)
	_target_pitch = clamp(target_euler.x, target_pitch_rad, max_pitch_rad)
	_target_yaw = target_euler.y
	
	# Smooth rotation towards target
	_current_pitch = lerp(_current_pitch, _target_pitch, turret_rotation_speed * delta)
	_current_yaw = lerp(_current_yaw, _target_yaw, turret_rotation_speed * delta)
	
	# Apply rotation (relative to mount point)
	if gun_mount_point:
		gun_mount_point.rotation.x = _current_pitch
		gun_mount_point.rotation.y = _current_yaw
	else:
		rotation.x = _current_pitch
		rotation.y = _current_yaw

func look_at_direction(direction: Vector3) -> Vector3:
	var yaw = atan2(-direction.x, -direction.z)
	var pitch = asin(direction.y)
	return Vector3(pitch, yaw, 0)

## Attempt to fire the weapon
func try_fire() -> bool:
	if not can_fire():
		return false
	
	_fire_cooldown = fire_rate
	weapon_fired.emit(global_position + muzzle_offset, get_fire_direction())
	
	# Deduct ammo
	if max_ammo > 0:
		current_ammo -= 1
		if current_ammo <= 0:
			_start_reload()
	
	_execute_fire()
	return true

func can_fire() -> bool:
	if _is_reloading or _fire_cooldown > 0:
		return false
	
	if max_ammo > 0 and current_ammo <= 0:
		return false
	
	return true

func get_fire_direction() -> Vector3:
	var base_dir = -global_transform.basis.z
	
	# Apply spread
	if spread_degrees > 0:
		var spread_rad = deg_to_rad(spread_degrees)
		var random_spread = Vector3(
			randf_range(-spread_rad, spread_rad),
			randf_range(-spread_rad, spread_rad),
			randf_range(-spread_rad, spread_rad)
		)
		base_dir = (base_dir + random_spread).normalized()
	
	return base_dir

func _execute_fire() -> void:
	# Override in subclasses
	pass

func _start_reload() -> void:
	if _is_reloading:
		return
	_is_reloading = true
	_reload_timer = reload_time

func _finish_reload() -> void:
	_is_reloading = false
	current_ammo = max_ammo
	weapon_reloaded.emit()

## Get ammo percentage (0.0 to 1.0)
func get_ammo_percent() -> float:
	if max_ammo <= 0:
		return 1.0
	return float(current_ammo) / float(max_ammo)

## Check if currently reloading
func is_reloading() -> bool:
	return _is_reloading
