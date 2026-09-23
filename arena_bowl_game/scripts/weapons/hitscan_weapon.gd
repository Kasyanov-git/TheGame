class_name HitscanWeapon
extends BaseWeapon

## Hitscan Weapon (Instant Raycast)
## Sprint 2: Combat & Perks

@export_group("Hitscan Settings")
@export var range: float = 300.0
@export var damage_falloff_start: float = 150.0
@export var damage_falloff_end: float = 300.0
@export var max_damage_falloff: float = 0.5  # 50% damage at max range

@export_group("Visual")
@export var hit_effect_scene: PackedScene
@export var miss_effect_scene: PackedScene
@export var laser_material: StandardMaterial3D

var _hit_markers: Array[Node3D] = []

func _execute_fire() -> void:
	var muzzle_pos = global_position + muzzle_offset
	if gun_mount_point:
		muzzle_pos = gun_mount_point.global_position + muzzle_offset
	
	var fire_dir = get_fire_direction()
	
	# Perform raycast
	var from = muzzle_pos
	var to = from + fire_dir * range
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [_owner_vehicle] if _owner_vehicle else []
	query.collision_mask = 1 | 2 | 4  # Adjust layers as needed
	
	var result = space_state.intersect_ray(query)
	
	if result:
		var hit_pos = result.position
		var hit_body = result.collider
		var normal = result.normal
		
		# Calculate damage falloff
		var distance = from.distance_to(hit_pos)
		var actual_damage = _calculate_damage(distance)
		
		# Apply damage if target has health
		if hit_body.is_in_group("player"):
			var health = hit_body.get_node_or_null("HealthComponent")
			if health and (not _owner_vehicle or hit_body != _owner_vehicle):
				var attacker_id = _owner_vehicle.name if _owner_vehicle else ""
				health.take_damage(actual_damage, attacker_id)
		
		# Spawn hit effect
		_spawn_hit_effect(hit_pos, normal)
	else:
		# Missed - spawn effect at max range
		_spawn_miss_effect(to)

func _calculate_damage(distance: float) -> float:
	if distance <= damage_falloff_start:
		return damage
	
	if distance >= damage_falloff_end:
		return damage * max_damage_falloff
	
	# Linear falloff between start and end
	var t = (distance - damage_falloff_start) / (damage_falloff_end - damage_falloff_start)
	return damage * lerp(1.0, max_damage_falloff, t)

func _spawn_hit_effect(position: Vector3, normal: Vector3) -> void:
	if hit_effect_scene:
		var effect = hit_effect_scene.instantiate()
		effect.global_position = position
		effect.look_at(position + normal)
		get_tree().get_current_scene().add_child(effect)
		
		# Auto cleanup
		var timer = get_tree().create_timer(0.5)
		timer.timeout.connect(func(): effect.queue_free())
	else:
		# Create simple hit marker
		_create_simple_hit_marker(position, normal)

func _create_simple_hit_marker(position: Vector3, normal: Vector3) -> void:
	var marker = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.3, 0.3, 0.05)
	marker.mesh = box
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(1, 0.2, 0.2)
	material.emission_enabled = true
	material.emission = Color(1, 0.2, 0.2)
	material.emission_energy_multiplier = 3.0
	marker.material_override = material
	
	marker.global_position = position
	marker.look_at(position + normal)
	get_tree().get_current_scene().add_child(marker)
	
	# Auto cleanup
	var timer = get_tree().create_timer(0.3)
	timer.timeout.connect(func(): marker.queue_free())

func _spawn_miss_effect(position: Vector3) -> void:
	if miss_effect_scene:
		var effect = miss_effect_scene.instantiate()
		effect.global_position = position
		get_tree().get_current_scene().add_child(effect)
		
		# Auto cleanup
		var timer = get_tree().create_timer(0.3)
		timer.timeout.connect(func(): effect.queue_free())
