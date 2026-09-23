class_name CombatVehicle
extends Node3D

## Combat Vehicle - Integrates movement, weapons, and health
## Sprint 2: Combat & Perks

# Signals
signal vehicle_destroyed(vehicle_id: String, killer_id: String)
signal vehicle_respawned(vehicle_id: String)
signal weapon_fired(weapon_name: String)
signal boost_changed(current: float, max: float)

# Configuration
@export_group("Vehicle Settings")
@export var vehicle_id: String = "player_1"
@export var team_id: int = 0
@export var is_bot: bool = false

@export_group("Boost Settings")
@export var max_boost: float = 100.0
@export var boost_drain_rate: float = 30.0  # per second
@export var boost_regen_rate: float = 15.0  # per second
@export var boost_min_for_use: float = 10.0

# State
var current_boost: float
var _is_boosting: bool = false
var _speed_multiplier: float = 1.0
var _damage_multiplier: float = 1.0
var _speed_timer: float = 0.0
var _damage_timer: float = 0.0

# References
var _vehicle_controller: Node
var _health_component: HealthComponent
var _weapons: Array[BaseWeapon] = []
var _current_weapon_index: int = 0
var _gun_mount_point: Node3D

func _ready() -> void:
	add_to_group("player")
	current_boost = max_boost
	
	# Find components
	_vehicle_controller = get_node_or_null("ArcadeVehicleController")
	_health_component = get_node_or_null("HealthComponent")
	
	# Find gun mount point
	_gun_mount_point = get_node_or_null("GunMountPoint")
	if not _gun_mount_point:
		_gun_mount_point = get_node_or_null("WeaponMount")
	
	# Initialize weapons
	_initialize_weapons()
	
	# Connect health signals
	if _health_component:
		_health_component.on_vehicle_destroyed.connect(_on_vehicle_destroyed)
		_health_component.on_vehicle_respawned.connect(_on_vehicle_respawned)

func _initialize_weapons() -> void:
	# Find all weapon children
	for child in get_children():
		if child is BaseWeapon:
			_weapons.append(child)
			
			# Set gun mount point if not already set
			if child.gun_mount_point == null and _gun_mount_point:
				child.gun_mount_point = _gun_mount_point
			
			# Connect weapon fired signal
			if child.has_signal("weapon_fired"):
				child.weapon_fired.connect(_on_weapon_fired.bind(child.name))
	
	if _weapons.size() > 0:
		_current_weapon_index = 0

func _process(delta: float) -> void:
	# Handle boost regeneration/drain
	_update_boost(delta)
	
	# Handle temporary buffs
	_update_buffs(delta)
	
	# Handle weapon input
	if not _health_component or not _health_component.is_dead:
		_handle_weapon_input()

func _update_boost(delta: float) -> void:
	if _is_boosting and current_boost > boost_min_for_use:
		current_boost -= boost_drain_rate * delta
		if current_boost < 0:
			current_boost = 0
			_is_boosting = false
	elif not _is_boosting and current_boost < max_boost:
		current_boost += boost_regen_rate * delta
		if current_boost > max_boost:
			current_boost = max_boost
	
	boost_changed.emit(current_boost, max_boost)

func _update_buffs(delta: float) -> void:
	if _speed_timer > 0:
		_speed_timer -= delta
		if _speed_timer <= 0:
			_speed_multiplier = 1.0
	
	if _damage_timer > 0:
		_damage_timer -= delta
		if _damage_timer <= 0:
			_damage_multiplier = 1.0

func _handle_weapon_input() -> void:
	var viewport = get_viewport()
	if not viewport:
		return
	
	# Fire weapon (left mouse button)
	if Input.is_action_pressed("fire_weapon") and _weapons.size() > 0:
		var current_weapon = _weapons[_current_weapon_index]
		if current_weapon.try_fire():
			weapon_fired.emit(current_weapon.name)
	
	# Switch weapons
	if Input.is_action_just_pressed("next_weapon"):
		_current_weapon_index = (_current_weapon_index + 1) % _weapons.size()
	elif Input.is_action_just_pressed("prev_weapon"):
		_current_weapon_index = (_current_weapon_index - 1) % _weapons.size()
		if _current_weapon_index < 0:
			_current_weapon_index = _weapons.size() - 1

func _physics_process(delta: float) -> void:
	# Pass boost state to vehicle controller
	if _vehicle_controller and _vehicle_controller.has_method("set_boost_active"):
		var can_boost = current_boost > boost_min_for_use
		_vehicle_controller.call("set_boost_active", _is_boosting and can_boost)

## Enable boosting
func start_boost() -> void:
	if current_boost > boost_min_for_use:
		_is_boosting = true

## Stop boosting
func stop_boost() -> void:
	_is_boosting = false

## Refill boost (for pickups)
func refill_boost() -> void:
	current_boost = max_boost
	boost_changed.emit(current_boost, max_boost)

## Apply temporary speed multiplier
func apply_speed_multiplier(multiplier: float, duration: float) -> void:
	_speed_multiplier = multiplier
	_speed_timer = duration
	
	# Notify vehicle controller
	if _vehicle_controller and _vehicle_controller.has_method("set_speed_multiplier"):
		_vehicle_controller.call("set_speed_multiplier", multiplier, duration)

## Apply temporary damage multiplier
func apply_damage_multiplier(multiplier: float, duration: float) -> void:
	_damage_multiplier = multiplier
	_damage_timer = duration

## Get current weapon
func get_current_weapon() -> BaseWeapon:
	if _weapons.size() == 0:
		return null
	return _weapons[_current_weapon_index]

## Switch to specific weapon by index
func switch_weapon(index: int) -> void:
	if index >= 0 and index < _weapons.size():
		_current_weapon_index = index

## Get vehicle team
func get_team_id() -> int:
	return team_id

## Check if vehicle is alive
func is_alive() -> bool:
	return _health_component and not _health_component.is_dead

## Get current health
func get_health() -> float:
	if _health_component:
		return _health_component.current_health
	return 0.0

## Get max health
func get_max_health() -> float:
	if _health_component:
		return _health_component.max_health
	return 100.0

func _on_vehicle_destroyed(vehicle: Node, attacker_id: String) -> void:
	vehicle_destroyed.emit(vehicle_id, attacker_id)
	stop_boost()

func _on_vehicle_respawned(vehicle: Node) -> void:
	vehicle_respawned.emit(vehicle_id)
	current_boost = max_boost
	boost_changed.emit(current_boost, max_boost)

func _on_weapon_fired(muzzle_pos: Vector3, direction: Vector3, weapon_name: String) -> void:
	weapon_fired.emit(weapon_name)
