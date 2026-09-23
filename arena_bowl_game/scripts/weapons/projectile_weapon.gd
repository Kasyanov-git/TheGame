class_name ProjectileWeapon
extends BaseWeapon

## Arcade Fast Projectile Weapon
## Sprint 2: Combat & Perks

@export_group("Projectile Settings")
@export var projectile_speed: float = 120.0
@export var projectile_lifetime: float = 3.0
@export var projectile_radius: float = 0.8
@export var projectile_scene: PackedScene  # Assign projectile scene
@export var muzzle_flash_scene: PackedScene
@export var impact_effect_scene: PackedScene

@export_group("Physics")
@export var projectile_mass: float = 1.0
@export var explosion_radius: float = 2.0
@export var explosion_damage: float = 10.0  # Splash damage

var _projectile_pool: Array[Node3D] = []

func _ready() -> void:
	super._ready()
	# Initialize projectile pool if needed
	# for i in range(10):
	# 	var proj = _create_projectile()
	# 	proj.set_process(false)
	# 	_projectile_pool.append(proj)

func _execute_fire() -> void:
	var muzzle_pos = global_position + muzzle_offset
	if gun_mount_point:
		muzzle_pos = gun_mount_point.global_position + muzzle_offset
	
	var fire_dir = get_fire_direction()
	
	# Spawn projectile
	var projectile = _spawn_projectile(muzzle_pos, fire_dir)
	
	if projectile:
		projectile.set_as_top_level(true)
		get_tree().get_current_scene().add_child(projectile)
		
		# Setup projectile
		if projectile is Area3D:
			_setup_area_projectile(projectile, muzzle_pos, fire_dir)
		elif projectile is RigidBody3D:
			_setup_rigidbody_projectile(projectile, muzzle_pos, fire_dir)
	
	# Spawn muzzle flash
	_spawn_muzzle_flash(muzzle_pos, fire_dir)

func _spawn_projectile(position: Vector3, direction: Vector3) -> Node3D:
	if projectile_scene:
		var proj = projectile_scene.instantiate()
		return proj
	else:
		# Create default projectile
		return _create_default_projectile()

func _create_default_projectile() -> Area3D:
	var area = Area3D.new()
	area.name = "Projectile"
	
	# Collision shape
	var collision = CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var sphere = SphereShape3D.new()
	sphere.radius = projectile_radius
	collision.shape = sphere
	area.add_child(collision)
	
	# Visual (optional simple mesh)
	var mesh = MeshInstance3D.new()
	mesh.name = "Mesh"
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = projectile_radius * 0.5
	sphere_mesh.height = projectile_radius
	mesh.mesh = sphere_mesh
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(1, 0.8, 0.2)
	material.emission_enabled = true
	material.emission = Color(1, 0.6, 0.1)
	material.emission_energy_multiplier = 2.0
	mesh.material_override = material
	mesh.position.y = projectile_radius * 0.5
	area.add_child(mesh)
	
	# Script for projectile behavior
	var script = GDScript.new()
	script.source_code = _get_projectile_script_source()
	area.set_script(script)
	
	return area

func _get_projectile_script_source() -> String:
	return """
extends Area3D

var velocity: Vector3 = Vector3.ZERO
var lifetime: float = 3.0
var damage: float = 15.0
var owner_id: String = ""
var explosion_radius: float = 2.0
var explosion_damage: float = 10.0

func setup(initial_velocity: Vector3, life: float, dmg: float, eid: String, exp_radius: float, exp_dmg: float) -> void:
\tvelocity = initial_velocity
\tlifetime = life
\tdamage = dmg
\towner_id = eid
\texplosion_radius = exp_radius
\texplosion_damage = exp_dmg

func _physics_process(delta: float) -> void:
\tlifetime -= delta
\tif lifetime <= 0:
\t\tqueue_free()
\t\treturn
\t
\tglobal_position += velocity * delta

func _on_body_entered(body: Node3D) -> void:
\tif body.is_in_group("player"):
\t\tvar health = body.get_node_or_null("HealthComponent")
\t\tif health and body.name != owner_id:
\t\t\thealth.take_damage(damage, owner_id)
\t\tqueue_free()
\telif not body.is_in_group("player") and not body.is_in_group("projectile"):
\t\t# Hit environment - create explosion
\t\t_create_explosion(global_position)
\t\tqueue_free()

func _create_explosion(pos: Vector3) -> void:
\tvar space_state = get_world_3d().direct_space_state
\tvar query = PhysicsShapeQueryParameters3D.new()
\tvar sphere = SphereShape3D.new()
\tsphere.radius = explosion_radius
\tquery.shape = sphere
\tquery.transform = Transform3D.IDENTITY.translated(pos)
\tquery.exclude = [self]
\t
\tvar results = space_state.intersect_shape(query)
\tfor result in results:
\t\tvar collider = result.collider
\t\tvar health = collider.get_node_or_null("HealthComponent")
\t\tif health:
\t\t\thealth.take_damage(explosion_damage, owner_id)
"""

func _setup_area_projectile(area: Area3D, position: Vector3, direction: Vector3) -> void:
	area.global_position = position
	
	# Connect signals if not already connected
	if not area.body_entered.is_connected(_on_projectile_hit):
		area.body_entered.connect(_on_projectile_hit.bind(area))
	
	# Set custom data via call if method exists
	if area.has_method("setup"):
		var owner_id = _owner_vehicle.name if _owner_vehicle else ""
		area.call("setup", direction * projectile_speed, projectile_lifetime, damage, owner_id, explosion_radius, explosion_damage)

func _setup_rigidbody_projectile(rb: RigidBody3D, position: Vector3, direction: Vector3) -> void:
	rb.global_position = position
	rb.linear_velocity = direction * projectile_speed
	rb.mass = projectile_mass

func _spawn_muzzle_flash(position: Vector3, direction: Vector3) -> void:
	if muzzle_flash_scene:
		var flash = muzzle_flash_scene.instantiate()
		flash.global_position = position
		flash.look_at(position + direction)
		get_tree().get_current_scene().add_child(flash)
		
		# Auto cleanup after animation
		var timer = get_tree().create_timer(0.1)
		timer.timeout.connect(func(): flash.queue_free())

func _on_projectile_hit(body: Node3D, projectile: Area3D) -> void:
	if body.is_in_group("player"):
		var health = body.get_node_or_null("HealthComponent")
		if health and (not _owner_vehicle or body != _owner_vehicle):
			var attacker_id = _owner_vehicle.name if _owner_vehicle else ""
			health.take_damage(damage, attacker_id)
	
	projectile.queue_free()
