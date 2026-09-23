extends RigidBody3D
class_name ArcadeVehicleController

## Arcade Vehicle Controller - Rocket League Style
## Sprint 1 MVP Implementation

#region Exported Parameters

@export_group("Engine & Speed")
@export_range(0, 100) var max_speed: float = 45.0
@export_range(0, 200) var engine_force: float = 80.0
@export_range(0, 5) var brake_force: float = 120.0
@export_range(1.0, 3.0) var boost_multiplier: float = 1.7

@export_group("Steering & Handling")
@export_range(0, 60) var steering_limit: float = 35.0
@export_range(0, 1) var drift_grip_factor: float = 0.35
@export_range(0, 10) var air_stabilization_torque: float = 5.0

@export_group("Downforce & Physics")
@export_range(0, 50) var downforce_strength: float = 15.0
@export_range(0, 1) var ground_grip: float = 0.92
@export_range(0, 1) var lateral_grip: float = 0.85

@export_group("Raycast Suspension")
@export var suspension_length: float = 0.4
@export var suspension_stiffness: float = 80.0
@export var suspension_damping: float = 15.0
@export var wheel_radius: float = 0.35

#endregion

#region Private Variables

var input_vector: Vector2 = Vector2.ZERO
var is_boosting: bool = false
var is_drifting: bool = false
var is_grounded: bool = false
var current_steering: float = 0.0
var velocity_local: Vector3 = Vector3.ZERO

# Raycast wheels for suspension simulation
var wheel_raycasters: Array[RayCast3D] = []
var wheel_positions: Array[Vector3] = [
	Vector3(-0.8, -0.3, 1.0),   # Front Left
	Vector3(0.8, -0.3, 1.0),    # Front Right
	Vector3(-0.8, -0.3, -1.0),  # Rear Left
	Vector3(0.8, -0.3, -1.0)    # Rear Right
]

#endregion

#region Node References

@onready var mesh_container: Node3D = $MeshContainer
@onready var camera_pivot: Node3D = $CameraPivot
@onready var spawn_points: Node3D = $SpawnPoints
@onready var weapon_hardpoints: Node3D = $WeaponHardpoints

#endregion

func _ready() -> void:
	# Configure physics body
	mass = 150.0
	inertia = Vector3(500, 800, 500)
	angular_damp = 2.0
	linear_damp = 0.1
	
	# Setup wheel raycasts
	setup_wheel_raycasters()
	
	# Freeze rotation initially for stability
	freeze_rotation_mode = RigidBody3D.FREEZE_ROTATION_DYNAMIC

func setup_wheel_raycasters() -> void:
	# Create raycasters for each wheel position (used for ground detection & suspension force)
	for i in range(4):
		var raycaster = RayCast3D.new()
		raycaster.name = "WheelRaycast_%d" % i
		raycaster.target_position = Vector3(0, -suspension_length - wheel_radius, 0)
		raycaster.collision_mask = 1 # Ground layer
		add_child(raycaster)
		wheel_raycasters.append(raycaster)

func _physics_process(delta: float) -> void:
	_update_speed_multiplier(delta)
	_handle_input()
	_apply_engine_forces(delta)
	_apply_steering(delta)
	_apply_lateral_grip(delta)
	_apply_downforce(delta)
	_apply_suspension_forces(delta)
	_apply_air_stabilization(delta)
	_update_camera_pivot(delta)

func _handle_input() -> void:
	# Get input vector (WASD / Arrow Keys / Gamepad)
	input_vector.x = Input.get_axis("ui_left", "ui_right")
	input_vector.y = Input.get_axis("ui_up", "ui_down")
	
	# Normalize to prevent faster diagonal movement
	if input_vector.length() > 1.0:
		input_vector = input_vector.normalized()
	
	# Boost input (Shift / Gamepad Button)
	is_boosting = Input.is_key_pressed(KEY_SHIFT) or Input.is_action_pressed("boost")
	
	# Drift input (Space / Gamepad Button)
	is_drifting = Input.is_key_pressed(KEY_SPACE) or Input.is_action_pressed("drift")

func _apply_engine_forces(delta: float) -> void:
	velocity_local = transform.basis.inverse() * linear_velocity
	
	# Calculate effective max speed
	var effective_max_speed = get_effective_max_speed()
	
	# Apply throttle/brake force along local Z axis
	var throttle_force = -input_vector.y * engine_force
	
	# Limit speed in forward/backward direction
	if abs(velocity_local.z) < effective_max_speed or throttle_force < 0:
		apply_force(transform.basis * Vector3(0, 0, throttle_force))
	
	# Apply braking when opposite input
	if input_vector.y == 0 and abs(velocity_local.z) > 1.0:
		var brake_direction = -sign(velocity_local.z)
		apply_force(transform.basis * Vector3(0, 0, brake_direction * brake_force * 0.5))

func _apply_steering(delta: float) -> void:
	# Reduce steering at high speeds for stability
	var speed_factor = clamp(abs(velocity_local.z) / max_speed, 0, 1)
	var dynamic_steering_limit = steering_limit * (1.0 - speed_factor * 0.4)
	
	# Smooth steering interpolation
	var target_steering = input_vector.x * dynamic_steering_limit
	current_steering = lerp(current_steering, target_steering, delta * 8.0)
	
	# Apply rotation around Y axis (yaw)
	var steer_torque = current_steering * 0.8
	apply_torque(transform.basis * Vector3(0, steer_torque, 0))
	
	# Counter-steer effect during drift
	if is_drifting and abs(input_vector.x) > 0.1:
		apply_torque(transform.basis * Vector3(0, -current_steering * 0.3, 0))

func _apply_lateral_grip(delta: float) -> void:
	# Dampen lateral (sideways) velocity for grip
	velocity_local = transform.basis.inverse() * linear_velocity
	
	var grip_factor = ground_grip if is_grounded else 0.3
	if is_drifting:
		grip_factor = drift_grip_factor
	
	# Apply lateral damping
	var lateral_velocity = Vector3(velocity_local.x, 0, 0)
	var damped_lateral = lateral_velocity * (1.0 - grip_factor * lateral_grip * delta)
	
	# Reconstruct velocity with damped lateral component
	var new_velocity_local = Vector3(damped_lateral.x, velocity_local.y, velocity_local.z)
	linear_velocity = transform.basis * new_velocity_local

func _apply_downforce(delta: float) -> void:
	# Apply downward force proportional to speed (keeps car on walls/curves)
	var speed = linear_velocity.length()
	var downforce_magnitude = downforce_strength * (speed / max_speed)
	
	# Apply force in world down direction
	apply_central_force(Vector3.DOWN * downforce_magnitude * mass)

func _apply_suspension_forces(delta: float) -> void:
	# Simulate suspension using raycasts
	is_grounded = false
	var total_suspension_force = 0.0
	
	for i in range(4):
		var raycaster = wheel_raycasters[i]
		raycaster.force_raycast_update()
		
		if raycaster.is_colliding():
			is_grounded = true
			var distance = raycaster.get_collision_point().distance_to(global_position + wheel_positions[i])
			var compression = max(0, suspension_length - distance)
			
			# Spring force + damping
			var spring_force = compression * suspension_stiffness
			var damping_force = -get_point_velocity(global_position + wheel_positions[i]).y * suspension_damping
			
			total_suspension_force += (spring_force + damping_force)
	
	# Apply suspension force upward
	if total_suspension_force > 0:
		apply_central_force(Vector3.UP * total_suspension_force)

func _apply_air_stabilization(delta: float) -> void:
	# Stabilize orientation when airborne
	if not is_grounded and linear_velocity.length() > 5.0:
		var current_rotation = rotation
		var target_rotation = Vector3(
			lerp_angle(rotation.x, 0, delta * air_stabilization_torque),
			rotation.y,
			lerp_angle(rotation.z, 0, delta * air_stabilization_torque)
		)
		
		# Apply corrective torque
		var torque_correction = (target_rotation - current_rotation) * air_stabilization_torque * mass
		apply_torque(torque_correction)

func _update_camera_pivot(delta: float) -> void:
	# Update camera pivot position based on velocity for look-ahead effect
	if camera_pivot:
		var look_ahead = linear_velocity.normalized() * clamp(linear_velocity.length() * 0.1, 0, 2.0)
		camera_pivot.position = Vector3(0, 1.5, 0) + look_ahead * 0.3

# Public methods for external use
func set_boost(active: bool) -> void:
	is_boosting = active

func set_boost_active(active: bool) -> void:
	is_boosting = active

func set_drift(active: bool) -> void:
	is_drifting = active

func get_is_grounded() -> bool:
	return is_grounded

func get_speed() -> float:
	return linear_velocity.length()

func get_velocity_local() -> Vector3:
	return transform.basis.inverse() * linear_velocity

## Set temporary speed multiplier (for pickups)
var _speed_mult: float = 1.0
var _speed_mult_timer: float = 0.0

func set_speed_multiplier(multiplier: float, duration: float) -> void:
	_speed_mult = multiplier
	_speed_mult_timer = duration

func _update_speed_multiplier(delta: float) -> void:
	if _speed_mult_timer > 0:
		_speed_mult_timer -= delta
		if _speed_mult_timer <= 0:
			_speed_mult = 1.0

func get_effective_max_speed() -> float:
	var base_speed = max_speed * (boost_multiplier if is_boosting else 1.0)
	return base_speed * _speed_mult
