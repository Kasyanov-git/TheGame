extends Node3D
class_name SeamlessBowlArena

## Seamless Bowl Arena Generator
## Creates a smooth arena with no 90° angles for dynamic movement
## Sprint 1 MVP Implementation

#region Exported Parameters

@export_group("Arena Dimensions")
@export_range(10, 100) var arena_radius: float = 40.0
@export_range(5, 30) var arena_height: float = 15.0
@export_range(1, 20) var wall_height: float = 8.0
@export_range(0.5, 10) var fillet_radius: float = 5.0  # Rounded corner radius

@export_group("Wall Settings")
@export_range(0, 1) var wall_friction: float = 0.1
@export_range(0, 1) var wall_restitution: float = 0.3
@export var wall_collision_layer: int = 2
@export var wall_collision_mask: int = 1

@export_group("Floor Settings")
@export_range(0, 1) var floor_friction: float = 0.15
@export_range(0, 1) var floor_restitution: float = 0.25

@export_group("Visual Settings")
@export var use_grid_material: bool = true
@export var grid_color: Color = Color(0.2, 0.2, 0.25)
@export var accent_color: Color = Color(0.1, 0.6, 0.8)

#endregion

#region Private Variables

var arena_mesh_instance: MeshInstance3D
var collision_shape: CollisionShape3D
var physics_material: PhysicsMaterial

#endregion

func _ready() -> void:
	_generate_arena()

func _generate_arena() -> void:
	# Create physics material for sliding
	physics_material = PhysicsMaterial.new()
	physics_material.friction = wall_friction
	physics_material.bounce = wall_restitution
	
	# Generate the bowl mesh using CSG or primitive combination
	var bowl_mesh = _create_bowl_mesh()
	
	# Create MeshInstance3D
	arena_mesh_instance = MeshInstance3D.new()
	arena_mesh_instance.name = "ArenaMesh"
	arena_mesh_instance.mesh = bowl_mesh
	arena_mesh_instance.create_trimesh_collision()
	
	# Get the generated collision and configure it
	var collision_node = arena_mesh_instance.get_node_or_null("CollisionShape3D")
	if collision_node:
		collision_node.collision_layer = wall_collision_layer
		collision_node.collision_mask = wall_collision_mask
		
		# Apply physics material to all surfaces
		var shape = collision_node.shape
		if shape is ConcavePolygonShape3D:
			# For concave shapes, we need to set material on the body
			pass
	
	add_child(arena_mesh_instance)
	
	# Add visual material if enabled
	if use_grid_material:
		_apply_visual_material(bowl_mesh)

func _create_bowl_mesh() -> MeshDataTool:
	# Create a seamless bowl shape using CSGSphere and CSGBox subtraction
	var csg_tree = CSGCombiner3D.new()
	
	# Main bowl - large rounded capsule/sphere segment
	var bowl_csg = CSGSphere3D.new()
	bowl_csg.name = "BowlBase"
	bowl_csg.radius = arena_radius
	bowl_csg.rings = 32
	bowl_csg.columns = 64
	bowl_csg.top_angle = 90.0  # Cut off top to create bowl
	bowl_csg.mode = CSGShape3D.MODE_UNION
	
	# Inner hollow (to make it a surface, not solid)
	var inner_bowl = CSGSphere3D.new()
	inner_bowl.name = "InnerHollow"
	inner_bowl.radius = arena_radius - 1.0
	inner_bowl.rings = 32
	inner_bowl.columns = 64
	inner_bowl.top_angle = 90.0
	inner_bowl.mode = CSGShape3D.MODE_SUBTRACTION
	
	# Floor ring with filleted edges
	var floor_ring = CSGTorus3D.new()
	floor_ring.name = "FloorRing"
	floor_ring.inner_radius = arena_radius * 0.3
	floor_ring.outer_radius = arena_radius
	floor_ring.ring_scale = 1.0
	floor_ring.sides = 64
	floor_ring.mode = CSGShape3D.MODE_UNION
	
	# Wall ring (vertical barrier)
	var wall_csg = CSGTorus3D.new()
	wall_csg.name = "WallRing"
	wall_csg.inner_radius = arena_radius - 2.0
	wall_csg.outer_radius = arena_radius + 2.0
	wall_csg.ring_scale = wall_height / (arena_radius * 2)
	wall_csg.sides = 64
	wall_csg.mode = CSGShape3D.MODE_UNITION
	
	# Position walls at edge
	wall_csg.transform = Transform3D(Basis(), Vector3(0, arena_height * 0.5, 0))
	
	# Add all to combiner
	csg_tree.add_child(bowl_csg)
	csg_tree.add_child(inner_bowl)
	csg_tree.add_child(floor_ring)
	csg_tree.add_child(wall_csg)
	
	# Build the mesh
	add_child(csg_tree)
	
	# Force CSG update (in real scene this happens automatically)
	await get_tree().process_frame
	
	# Convert to mesh for better performance
	var mesh_data_tool = MeshDataTool.new()
	# Note: In actual implementation, you'd use CSGToMesh or bake the mesh
	
	# For MVP, return a simpler approach using primitive meshes
	return _create_simplified_bowl_mesh()

func _create_simplified_bowl_mesh() -> ArrayMesh:
	# Simplified approach: combine primitive shapes
	var mesh_array = ArrayMesh.new()
	
	# Create bowl from multiple ring segments
	var mesh_builder = ImmediateMesh.new()
	mesh_builder.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var segments = 64
	var vertical_segments = 8
	
	# Generate bowl surface vertices
	for i in range(segments):
		var angle1 = (float(i) / segments) * TAU
		var angle2 = (float(i + 1) / segments) * TAU
		
		for j in range(vertical_segments):
			var height_ratio1 = float(j) / vertical_segments
			var height_ratio2 = float(j + 1) / vertical_segments
			
			# Calculate radius at this height (wider at top, narrower at bottom)
			var radius1 = arena_radius * (0.4 + height_ratio1 * 0.6)
			var radius2 = arena_radius * (0.4 + height_ratio2 * 0.6)
			
			var y1 = -arena_height * 0.5 + height_ratio1 * arena_height
			var y2 = -arena_height * 0.5 + height_ratio2 * arena_height
			
			# Four corners of the quad
			var v1 = Vector3(cos(angle1) * radius1, y1, sin(angle1) * radius1)
			var v2 = Vector3(cos(angle2) * radius1, y1, sin(angle2) * radius1)
			var v3 = Vector3(cos(angle2) * radius2, y2, sin(angle2) * radius2)
			var v4 = Vector3(cos(angle1) * radius2, y2, sin(angle1) * radius2)
			
			# Create two triangles
			_add_quad(mesh_builder, v1, v2, v3, v4, Vector3.UP)
	
	mesh_builder.surface_end()
	
	# Add floor
	mesh_builder.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_floor_mesh(mesh_builder)
	mesh_builder.surface_end()
	
	# Add wall ring
	mesh_builder.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_wall_mesh(mesh_builder)
	mesh_builder.surface_end()
	
	return mesh_builder

func _add_quad(builder: ImmediateMesh, v1: Vector3, v2: Vector3, v3: Vector3, v4: Vector3, normal: Vector3) -> void:
	# Triangle 1
	builder.set_normal(normal)
	builder.add_vertex(v1)
	builder.add_vertex(v2)
	builder.add_vertex(v3)
	
	# Triangle 2
	builder.add_vertex(v1)
	builder.add_vertex(v3)
	builder.add_vertex(v4)

func _add_floor_mesh(builder: ImmediateMesh) -> void:
	var segments = 64
	var inner_radius = arena_radius * 0.3
	var outer_radius = arena_radius
	
	for i in range(segments):
		var angle1 = (float(i) / segments) * TAU
		var angle2 = (float(i + 1) / segments) * TAU
		
		var v1 = Vector3(cos(angle1) * inner_radius, -arena_height * 0.5, sin(angle1) * inner_radius)
		var v2 = Vector3(cos(angle2) * inner_radius, -arena_height * 0.5, sin(angle2) * inner_radius)
		var v3 = Vector3(cos(angle2) * outer_radius, -arena_height * 0.5, sin(angle2) * outer_radius)
		var v4 = Vector3(cos(angle1) * outer_radius, -arena_height * 0.5, sin(angle1) * outer_radius)
		
		_add_quad(builder, v1, v2, v3, v4, Vector3.UP)

func _add_wall_mesh(builder: ImmediateMesh) -> void:
	var segments = 64
	var wall_top_y = arena_height * 0.5
	
	for i in range(segments):
		var angle1 = (float(i) / segments) * TAU
		var angle2 = (float(i + 1) / segments) * TAU
		
		var v1 = Vector3(cos(angle1) * (arena_radius - 2), -arena_height * 0.5, sin(angle1) * (arena_radius - 2))
		var v2 = Vector3(cos(angle2) * (arena_radius - 2), -arena_height * 0.5, sin(angle2) * (arena_radius - 2))
		var v3 = Vector3(cos(angle2) * (arena_radius + 2), wall_top_y, sin(angle2) * (arena_radius + 2))
		var v4 = Vector3(cos(angle1) * (arena_radius + 2), wall_top_y, sin(angle1) * (arena_radius + 2))
		
		# Calculate inward-facing normal
		var normal = Vector3(cos((angle1 + angle2) * 0.5), 0, sin((angle1 + angle2) * 0.5)).normalized()
		_add_quad(builder, v1, v2, v3, v4, normal)

func _apply_visual_material(mesh: ArrayMesh) -> void:
	if not arena_mesh_instance:
		return
	
	# Create simple grid material
	var material = StandardMaterial3D.new()
	material.albedo_color = grid_color
	material.roughness = 0.7
	metallic = 0.3
	
	# Enable wireframe/grid effect
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = accent_color
	
	arena_mesh_instance.set_surface_override_material(0, material)

# Public API
func get_arena_radius() -> float:
	return arena_radius

func get_arena_center() -> Vector3:
	return global_position

func get_random_spawn_position() -> Vector3:
	var angle = randf() * TAU
	var radius = randf_range(0, arena_radius * 0.7)
	return Vector3(cos(angle) * radius, arena_height * 0.5, sin(angle) * radius)
