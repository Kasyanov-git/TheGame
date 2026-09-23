extends Camera3D
class_name DynamicVehicleCamera

## Dynamic Camera System for Arcade Vehicle
## Sprint 1 MVP Implementation

#region Exported Parameters

@export_group("Spring Arm Settings")
@export_range(0, 20) var spring_arm_length: float = 6.0
@export_range(-90, 0) var spring_arm_angle: float = -15.0
@export_range(0, 5) var spring_arm_height_offset: float = 2.0

@export_group("Camera Smoothing")
@export_range(0, 1) var position_lerp_speed: float = 0.12
@export_range(0, 1) var rotation_lerp_speed: float = 0.15
@export_range(0, 1) var look_ahead_factor: float = 0.3

@export_group("Dynamic FOV")
@export_range(60, 120) var base_fov: float = 75.0
@export_range(60, 120) var boost_fov: float = 90.0
@export_range(0, 100) var fov_transition_speed: float = 2.0

@export_group("Look Ahead")
@export_range(0, 5) var look_ahead_distance: float = 3.0
@export_range(0, 1) var look_ahead_smoothness: float = 0.1

#endregion

#region Private Variables

var target_position: Vector3 = Vector3.ZERO
var target_focus: Vector3 = Vector3.ZERO
var current_fov: float = 75.0
var vehicle_velocity: Vector3 = Vector3.ZERO
var is_boosting: bool = false

#endregion

#region Node References

var spring_arm: SpringArm3D
var vehicle_target: RigidBody3D

#endregion

func _ready() -> void:
	# Setup SpringArm3D programmatically
	spring_arm = SpringArm3D.new()
	spring_arm.name = "SpringArm"
	spring_arm.spring_length = spring_arm_length
	spring_arm.collision_mask = 2 # Environment layer
	spring_arm.add_child(self)
	
	# Configure camera
	current_fov = base_fov
	fov = current_fov
	
	# Add to scene (assumes parent will be set externally or via scene tree)
	if get_parent():
		get_parent().add_child(spring_arm)

func _physics_process(delta: float) -> void:
	if not vehicle_target:
		find_vehicle_target()
		return
	
	_update_vehicle_data()
	_calculate_target_positions()
	_apply_smoothing(delta)
	_update_dynamic_fov(delta)

func find_vehicle_target() -> void:
	# Try to find vehicle in parent or siblings
	var parent = get_parent()
	if parent and parent is RigidBody3D:
		vehicle_target = parent
	elif parent and parent.has_node("../"):
		var sibling = parent.get_sibling(0)
		if sibling and sibling is RigidBody3D:
			vehicle_target = sibling

func _update_vehicle_data() -> void:
	if vehicle_target:
		vehicle_velocity = vehicle_target.linear_velocity
		# Check if boosting (can be extended with signal from vehicle)
		is_boosting = vehicle_velocity.length() > 40.0

func _calculate_target_positions() -> void:
	if not vehicle_target:
		return
	
	# Calculate target camera position relative to vehicle
	var vehicle_basis = vehicle_target.transform.basis
	
	# Spring arm offset (behind and above vehicle)
	var base_offset = Vector3(0, spring_arm_height_offset, -spring_arm_length)
	var rotated_offset = vehicle_basis * base_offset
	
	# Apply angle tilt
	var tilt_rotation = Basis(Vector3.RIGHT, deg_to_rad(spring_arm_angle))
	rotated_offset = tilt_rotation * rotated_offset
	
	target_position = vehicle_target.global_position + rotated_offset
	
	# Calculate focus point with look-ahead
	var look_ahead_vector = vehicle_velocity.normalized() * look_ahead_distance * look_ahead_factor
	target_focus = vehicle_target.global_position + Vector3(0, spring_arm_height_offset, 0) + look_ahead_vector

func _apply_smoothing(delta: float) -> void:
	# Smooth position interpolation
	spring_arm.global_position = spring_arm.global_position.lerp(target_position, position_lerp_speed)
	
	# Smooth rotation to look at focus point
	if target_focus != Vector3.ZERO:
		var target_basis = Basis()
		target_basis = target_basis.looking_at(target_focus - spring_arm.global_position, Vector3.UP)
		spring_arm.global_basis = spring_arm.global_basis.slerp(target_basis, rotation_lerp_speed)

func _update_dynamic_fov(delta: float) -> void:
	# Interpolate FOV based on boost state
	var target_fov = boost_fov if is_boosting else base_fov
	current_fov = lerp(current_fov, target_fov, delta * fov_transition_speed)
	fov = current_fov

# Public API
func set_vehicle_target(vehicle: RigidBody3D) -> void:
	vehicle_target = vehicle

func set_boost_state(boosting: bool) -> void:
	is_boosting = boosting

func get_current_fov() -> float:
	return current_fov

func get_spring_arm() -> SpringArm3D:
	return spring_arm
