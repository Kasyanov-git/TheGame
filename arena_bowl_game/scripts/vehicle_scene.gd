extends Node3D
class_name VehicleScene

## Complete Vehicle Scene Template
## Pre-configured scene with mesh, camera, and spawn points
## Sprint 1 MVP Implementation

#region Exported Parameters

@export var vehicle_color: Color = Color(0.2, 0.6, 1.0)
@export var headlight_color: Color = Color(1.0, 0.9, 0.7)
@export var taillight_color: Color = Color(1.0, 0.1, 0.1)

#endregion

#region Node References

@onready var vehicle_body: RigidBody3D = $ArcadeVehicleController
@onready var mesh_container: Node3D = $ArcadeVehicleController/MeshContainer
@onready var camera_pivot: Node3D = $ArcadeVehicleController/CameraPivot
@onready var spawn_points: Node3D = $ArcadeVehicleController/SpawnPoints
@onready var weapon_hardpoints: Node3D = $ArcadeVehicleController/WeaponHardpoints

#endregion

func _ready() -> void:
	_setup_vehicle_mesh()
	_setup_lights()
	_configure_collision()

func _setup_vehicle_mesh() -> void:
	if not mesh_container:
		return
	
	# Create simple car body mesh (box with styling)
	var body_mesh = BoxMesh.new()
	body_mesh.size = Vector3(1.6, 0.6, 3.5)
	
	var body_instance = MeshInstance3D.new()
	body_instance.name = "BodyMesh"
	body_instance.mesh = body_mesh
	
	# Apply color material
	var material = StandardMaterial3D.new()
	material.albedo_color = vehicle_color
	material.roughness = 0.5
	material.metallic = 0.7
	body_instance.set_surface_override_material(0, material)
	
	mesh_container.add_child(body_instance)
	
	# Add cabin (top part)
	var cabin_mesh = BoxMesh.new()
	cabin_mesh.size = Vector3(1.4, 0.5, 2.0)
	
	var cabin_instance = MeshInstance3D.new()
	cabin_instance.name = "CabinMesh"
	cabin_instance.mesh = cabin_mesh
	cabin_instance.position = Vector3(0, 0.55, -0.2)
	
	var cabin_material = StandardMaterial3D.new()
	cabin_material.albedo_color = vehicle_color.darkened(0.2)
	cabin_material.roughness = 0.3
	cabin_material.metallic = 0.9
	cabin_instance.set_surface_override_material(0, cabin_material)
	
	mesh_container.add_child(cabin_instance)
	
	# Add wheel visual placeholders
	_create_wheel_visuals()

func _create_wheel_visuals() -> void:
	var wheel_positions = [
		Vector3(-0.85, -0.3, 1.2),   # Front Left
		Vector3(0.85, -0.3, 1.2),    # Front Right
		Vector3(-0.85, -0.3, -1.2),  # Rear Left
		Vector3(0.85, -0.3, -1.2)    # Rear Right
	]
	
	for i in range(4):
		var wheel_mesh = CylinderMesh.new()
		wheel_mesh.radius = 0.35
		wheel_mesh.height = 0.3
		
		var wheel_instance = MeshInstance3D.new()
		wheel_instance.name = "Wheel_%d" % i
		wheel_instance.mesh = wheel_mesh
		wheel_instance.position = wheel_positions[i]
		wheel_instance.rotation.z = PI / 2.0
		
		var wheel_material = StandardMaterial3D.new()
		wheel_material.albedo_color = Color(0.15, 0.15, 0.15)
		wheel_material.roughness = 0.9
		wheel_instance.set_surface_override_material(0, wheel_material)
		
		mesh_container.add_child(wheel_instance)

func _setup_lights() -> void:
	if not mesh_container:
		return
	
	# Headlights (forward-facing spotlights)
	var left_headlight = SpotLight3D.new()
	left_headlight.name = "LeftHeadlight"
	left_headlight.position = Vector3(-0.6, 0.2, 1.75)
	left_headlight.light_color = headlight_color
	left_headlight.light_energy = 2.0
	left_headlight.spot_angle = 45
	left_headlight.transform.basis = Basis(Vector3.RIGHT, deg_to_rad(-10))
	mesh_container.add_child(left_headlight)
	
	var right_headlight = SpotLight3D.new()
	right_headlight.name = "RightHeadlight"
	right_headlight.position = Vector3(0.6, 0.2, 1.75)
	right_headlight.light_color = headlight_color
	right_headlight.light_energy = 2.0
	right_headlight.spot_angle = 45
	right_headlight.transform.basis = Basis(Vector3.RIGHT, deg_to_rad(-10))
	mesh_container.add_child(right_headlight)
	
	# Taillights (omni lights for glow effect)
	var left_taillight = OmniLight3D.new()
	left_taillight.name = "LeftTaillight"
	left_taillight.position = Vector3(-0.6, 0.3, -1.75)
	left_taillight.light_color = taillight_color
	left_taillight.light_energy = 0.5
	left_taillight.light_range = 3.0
	mesh_container.add_child(left_taillight)
	
	var right_taillight = OmniLight3D.new()
	right_taillight.name = "RightTaillight"
	right_taillight.position = Vector3(0.6, 0.3, -1.75)
	right_taillight.light_color = taillight_color
	right_taillight.light_energy = 0.5
	right_taillight.light_range = 3.0
	mesh_container.add_child(right_taillight)

func _configure_collision() -> void:
	if not vehicle_body:
		return
	
	# Set collision layer and mask
	vehicle_body.collision_layer = 4  # Vehicle layer
	vehicle_body.collision_mask = 3   # Ground (1) + Environment (2)
	
	# Add collision shape if not present
	var collision_shape = vehicle_body.get_node_or_null("CollisionShape3D")
	if not collision_shape:
		collision_shape = CollisionShape3D.new()
		collision_shape.name = "CollisionShape3D"
		
		var shape = BoxShape3D.new()
		shape.size = Vector3(1.6, 0.8, 3.5)
		collision_shape.shape = shape
		
		vehicle_body.add_child(collision_shape)

# Public API for external control
func get_vehicle_body() -> RigidBody3D:
	return vehicle_body

func set_vehicle_color(color: Color) -> void:
	vehicle_color = color
	if mesh_container:
		var body_mesh = mesh_container.get_node_or_null("BodyMesh")
		if body_mesh and body_mesh is MeshInstance3D:
			var material = body_mesh.get_surface_override_material(0)
			if material:
				material.albedo_color = color

func reset_vehicle(position: Vector3, rotation: Vector3) -> void:
	if vehicle_body:
		vehicle_body.global_position = position
		vehicle_body.rotation = rotation
		vehicle_body.linear_velocity = Vector3.ZERO
		vehicle_body.angular_velocity = Vector3.ZERO
