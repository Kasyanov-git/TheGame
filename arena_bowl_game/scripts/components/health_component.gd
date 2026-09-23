class_name HealthComponent
extends Node

## Health, Damage & Death Component for Vehicles and Objects
## Sprint 2: Combat & Perks

# Signals
signal health_changed(new_hp: float, max_hp: float)
signal hit_registered(target_position: Vector3, damage: float, is_kill: bool)
signal on_vehicle_destroyed(vehicle: Node, attacker_id: String)
signal on_vehicle_respawned(vehicle: Node)

# Configuration
@export_group("Health Settings")
@export var max_health: float = 100.0
@export var respawn_delay: float = 4.0
@export var invincibility_after_respawn: float = 2.0

# State
var current_health: float
var is_dead: bool = false
var is_invincible: bool = false
var _attacker_id: String = ""
var _respawn_timer: float = 0.0
var _invincibility_timer: float = 0.0

# References
var _vehicle_node: Node3D
var _original_collision_mask: int = 0
var _original_collision_layer: int = 0

func _ready() -> void:
	current_health = max_health
	_vehicle_node = get_parent()
	
	# Store original collision settings if parent has collision
	if _vehicle_node is RigidBody3D or _vehicle_node.has_node("CollisionShape3D"):
		var collision_node = _get_collision_node(_vehicle_node)
		if collision_node and collision_node.shape:
			_original_collision_mask = collision_node.collision_mask
			_original_collision_layer = collision_node.collision_layer
	
	# Start invincible after spawn
	_start_invincibility()

func _get_collision_node(node: Node) -> CollisionShape3D:
	if node is CollisionShape3D:
		return node
	for child in node.get_children():
		var result = _get_collision_node(child)
		if result:
			return result
	return null

func _process(delta: float) -> void:
	if is_dead:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			respawn()
	
	if is_invincible:
		_invincibility_timer -= delta
		if _invincibility_timer <= 0.0:
			is_invincible = false

## Take damage from an attacker
func take_damage(amount: float, attacker_id: String = "") -> void:
	if is_dead or is_invincible:
		return
	
	current_health = max(0.0, current_health - amount)
	_attacker_id = attacker_id
	
	health_changed.emit(current_health, max_health)
	
	var hit_pos = _vehicle_node.global_position if _vehicle_node else Vector3.ZERO
	var is_kill = current_health <= 0.0
	hit_registered.emit(hit_pos, amount, is_kill)
	
	if current_health <= 0.0:
		die()

## Apply healing
func heal(amount: float) -> void:
	if is_dead:
		return
	
	current_health = min(max_health, current_health + amount)
	health_changed.emit(current_health, max_health)

## Apply shield (temporary extra HP)
func apply_shield(duration: float, shield_amount: float = 50.0) -> void:
	if is_dead:
		return
	
	# For simplicity, just heal and make invincible temporarily
	heal(shield_amount)
	is_invincible = true
	_invincibility_timer = duration

## Kill the vehicle
func die() -> void:
	if is_dead:
		return
	
	is_dead = true
	_disable_physics()
	on_vehicle_destroyed.emit(_vehicle_node, _attacker_id)

## Respawn the vehicle
func respawn() -> void:
	if not is_dead:
		return
	
	is_dead = false
	current_health = max_health
	_enable_physics()
	_start_invincibility()
	on_vehicle_respawned.emit(_vehicle_node)
	health_changed.emit(current_health, max_health)

func _start_invincibility() -> void:
	is_invincible = true
	_invincibility_timer = invincibility_after_respawn

func _disable_physics() -> void:
	if _vehicle_node is RigidBody3D:
		_vehicle_node.mode = RigidBody3D.MODE_SLEEPING
		_vehicle_node.freeze = true
	
	# Disable collisions
	var collision_node = _get_collision_node(_vehicle_node)
	if collision_node:
		collision_node.set_deferred("disabled", true)
	
	# Hide visual representation
	var mesh_node = _get_mesh_node(_vehicle_node)
	if mesh_node:
		mesh_node.visible = false

func _enable_physics() -> void:
	if _vehicle_node is RigidBody3D:
		_vehicle_node.mode = RigidBody3D.MODE_RIGID
		_vehicle_node.freeze = false
	
	# Re-enable collisions
	var collision_node = _get_collision_node(_vehicle_node)
	if collision_node:
		collision_node.set_deferred("disabled", false)
		collision_node.collision_mask = _original_collision_mask
		collision_node.collision_layer = _original_collision_layer
	
	# Show visual representation
	var mesh_node = _get_mesh_node(_vehicle_node)
	if mesh_node:
		mesh_node.visible = true

func _get_mesh_node(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var result = _get_mesh_node(child)
		if result:
			return result
	return null

## Get health percentage (0.0 to 1.0)
func get_health_percent() -> float:
	return current_health / max_health if max_health > 0.0 else 0.0

## Check if can be damaged
func can_take_damage() -> bool:
	return not is_dead and not is_invincible
