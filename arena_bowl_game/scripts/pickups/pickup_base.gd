class_name PickupBase
extends Area3D

## Base Pickup Component for Arena Power-ups
## Sprint 2: Combat & Perks

# Signals
signal pickup_collected(pickup_type: String, position: Vector3)
signal pickup_respawned(pickup_type: String, position: Vector3)

# Configuration
@export_group("Pickup Settings")
@export_enum("Nitro", "Health", "Shield", "SpeedBoost", "DamageBoost") var pickup_type: String = "Nitro"
@export var cooldown_time: float = 10.0
@export var respawn_animation_time: float = 1.0

@export_group("Effects")
@export var icon_scene: PackedScene
@export var collect_effect_scene: PackedScene
@export var respawn_effect_scene: PackedScene

@export_group("Audio")
@export var collect_sound: AudioStream
@export var respawn_sound: AudioStream

# State
var is_available: bool = true
var is_respawning: bool = false
var _respawn_timer: float = 0.0
var _spawn_position: Vector3

# References
var _icon_node: Node3D
var _audio_player: AudioStreamPlayer3D

func _ready() -> void:
	_spawn_position = global_position
	
	# Create audio player
	_audio_player = AudioStreamPlayer3D.new()
	_audio_player.name = "AudioStreamPlayer3D"
	add_child(_audio_player)
	
	# Create icon visual
	_create_icon_visual()
	
	# Connect body entered signal
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

func _create_icon_visual() -> void:
	var container = Node3D.new()
	container.name = "IconContainer"
	add_child(container)
	
	if icon_scene:
		_icon_node = icon_scene.instantiate()
		container.add_child(_icon_node)
	else:
		# Create default rotating cube icon
		_icon_node = _create_default_icon()
		container.add_child(_icon_node)
	
	_icon_node.position.y = 1.0

func _create_default_icon() -> MeshInstance3D:
	var mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.8, 0.8, 0.8)
	mesh.mesh = box
	
	var material = StandardMaterial3D.new()
	match pickup_type:
		"Nitro":
			material.albedo_color = Color(0.2, 0.6, 1.0)
			material.emission_enabled = true
			material.emission = Color(0.2, 0.6, 1.0)
			material.emission_energy_multiplier = 2.0
		"Health":
			material.albedo_color = Color(0.2, 1.0, 0.4)
			material.emission_enabled = true
			material.emission = Color(0.2, 1.0, 0.4)
			material.emission_energy_multiplier = 2.0
		"Shield":
			material.albedo_color = Color(1.0, 0.8, 0.2)
			material.emission_enabled = true
			material.emission = Color(1.0, 0.8, 0.2)
			material.emission_energy_multiplier = 2.0
		"SpeedBoost":
			material.albedo_color = Color(1.0, 0.2, 0.6)
			material.emission_enabled = true
			material.emission = Color(1.0, 0.2, 0.6)
			material.emission_energy_multiplier = 2.0
		"DamageBoost":
			material.albedo_color = Color(1.0, 0.3, 0.1)
			material.emission_enabled = true
			material.emission = Color(1.0, 0.3, 0.1)
			material.emission_energy_multiplier = 2.0
		_:
			material.albedo_color = Color(0.8, 0.8, 0.8)
	
	mesh.material_override = material
	return mesh

func _process(delta: float) -> void:
	if is_respawning:
		_respawn_timer -= delta
		
		# Rotate icon while waiting
		if _icon_node:
			_icon_node.rotation.y += delta * 2.0
			_icon_node.rotation.x = sin(_respawn_timer * 3.0) * 0.2
		
		if _respawn_timer <= 0.0:
			_respawn_pickup()
	elif is_available and _icon_node:
		# Idle rotation
		_icon_node.rotation.y += delta * 1.5
		_icon_node.position.y = 1.0 + sin(Time.get_ticks_msec() * 0.003) * 0.2

func _on_body_entered(body: Node3D) -> void:
	if not is_available or is_respawning:
		return
	
	# Check if body is a vehicle with pickup capability
	if body.is_in_group("player"):
		_try_collect(body)

func _try_collect(vehicle: Node3D) -> void:
	var success = false
	
	match pickup_type:
		"Nitro":
			success = _apply_nitro_boost(vehicle)
		"Health":
			success = _apply_health_repair(vehicle)
		"Shield":
			success = _apply_shield(vehicle)
		"SpeedBoost":
			success = _apply_speed_boost(vehicle)
		"DamageBoost":
			success = _apply_damage_boost(vehicle)
	
	if success:
		_collect_pickup()

func _apply_nitro_boost(vehicle: Node3D) -> bool:
	# Find vehicle controller and refill boost
	var controller = vehicle.get_node_or_null("ArcadeVehicleController")
	if controller and controller.has_method("refill_boost"):
		controller.call("refill_boost")
		return true
	# Fallback: check for boost property
	if vehicle.has_method("refill_boost"):
		vehicle.call("refill_boost")
		return true
	return true  # Assume success for now

func _apply_health_repair(vehicle: Node3D) -> bool:
	var health = vehicle.get_node_or_null("HealthComponent")
	if health:
		health.heal(35.0)
		return true
	return false

func _apply_shield(vehicle: Node3D) -> bool:
	var health = vehicle.get_node_or_null("HealthComponent")
	if health:
		health.apply_shield(6.0, 50.0)
		return true
	return false

func _apply_speed_boost(vehicle: Node3D) -> bool:
	# Temporary speed boost (implementation depends on vehicle controller)
	if vehicle.has_method("apply_speed_multiplier"):
		vehicle.call("apply_speed_multiplier", 1.3, 5.0)
		return true
	return true

func _apply_damage_boost(vehicle: Node3D) -> bool:
	# Temporary damage boost (implementation depends on weapon system)
	if vehicle.has_method("apply_damage_multiplier"):
		vehicle.call("apply_damage_multiplier", 1.5, 5.0)
		return true
	return true

func _collect_pickup() -> void:
	is_available = false
	
	# Spawn collect effect
	_spawn_collect_effect()
	
	# Play sound
	if collect_sound:
		_audio_player.stream = collect_sound
		_audio_player.play()
	
	# Emit signal
	pickup_collected.emit(pickup_type, _spawn_position)
	
	# Hide icon
	if _icon_node:
		_icon_node.visible = false
	
	# Start respawn timer
	_start_respawn()

func _start_respawn() -> void:
	is_respawning = true
	_respawn_timer = cooldown_time

func _respawn_pickup() -> void:
	is_respawning = false
	is_available = true
	
	# Show icon
	if _icon_node:
		_icon_node.visible = true
	
	# Spawn respawn effect
	_spawn_respawn_effect()
	
	# Play sound
	if respawn_sound:
		_audio_player.stream = respawn_sound
		_audio_player.play()
	
	# Emit signal
	pickup_respawned.emit(pickup_type, _spawn_position)

func _spawn_collect_effect() -> void:
	if collect_effect_scene:
		var effect = collect_effect_scene.instantiate()
		effect.global_position = _spawn_position
		get_tree().get_current_scene().add_child(effect)
		
		var timer = get_tree().create_timer(1.0)
		timer.timeout.connect(func(): effect.queue_free())

func _spawn_respawn_effect() -> void:
	if respawn_effect_scene:
		var effect = respawn_effect_scene.instantiate()
		effect.global_position = _spawn_position
		get_tree().get_current_scene().add_child(effect)
		
		var timer = get_tree().create_timer(1.0)
		timer.timeout.connect(func(): effect.queue_free())
