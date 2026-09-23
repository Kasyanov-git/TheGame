extends Node3D
class_name GameManager

## Main Game Manager - Sprint 1 MVP
## Handles game state, vehicle spawning, and scene coordination

#region Exported Parameters

@export var vehicle_scene: PackedScene
@export var arena_scene: PackedScene
@export var max_players: int = 4

#endregion

#region Private Variables

var vehicles: Array[Node3D] = []
var cameras: Array[Camera3D] = []
var current_arena: Node3D = null
var game_state: GameState = GameState.LOBBY

enum GameState {
	LOBBY,
	PLAYING,
	PAUSED,
	GAME_OVER
}

#endregion

#region Node References

@onready var vehicle_spawn_points: Node3D = $VehicleSpawnPoints
@onready var environment: WorldEnvironment = $WorldEnvironment

#endregion

func _ready() -> void:
	_setup_environment()
	_setup_input_map()
	load_arena()
	spawn_player_vehicle(0)

func _setup_environment() -> void:
	# Configure world environment for toon/cel-shading style
	if not environment:
		environment = WorldEnvironment.new()
		environment.name = "WorldEnvironment"
		add_child(environment)
	
	var env_resource = Environment.new()
	env_resource.background_mode = Environment.BG_COLOR
	env_resource.background_color = Color(0.15, 0.18, 0.22)
	
	# Ambient light
	env_resource.ambient_light_enabled = true
	env_resource.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env_resource.ambient_light_color = Color(0.4, 0.45, 0.5)
	env_resource.ambient_light_energy = 0.6
	
	# Glow for headlights/taillights
	env_resource.glow_enabled = true
	env_resource.glow_intensity = 0.8
	env_resource.glow_bloom = 0.3
	
	# SSAO for depth perception
	env_resource.ssao_enabled = true
	env_resource.ssao_intensity = 0.3
	
	environment.environment = env_resource
	
	# Add directional light (sun)
	var sun_light = DirectionalLight3D.new()
	sun_light.name = "Sun"
	sun_light.rotation_degrees = Vector3(-45, 45, 0)
	sun_light.light_energy = 1.2
	sun_light.shadow_enabled = true
	sun_light.shadow_size = 2048
	add_child(sun_light)

func _setup_input_map() -> void:
	# Ensure input actions are configured
	if not InputMap.has_action("boost"):
		InputMap.add_action("boost")
		var key = InputEventKey.new()
		key.keycode = KEY_SHIFT
		InputMap.action_add_event("boost", key)
	
	if not InputMap.has_action("drift"):
		InputMap.add_action("drift")
		var key = InputEventKey.new()
		key.keycode = KEY_SPACE
		InputMap.action_add_event("drift", key)
	
	if not InputMap.has_action("fire"):
		InputMap.add_action("fire")
		var key = InputEventKey.new()
		key.keycode = KEY_CTRL
		InputMap.action_add_event("fire", key)
	
	if not InputMap.has_action("camera_cycle"):
		InputMap.add_action("camera_cycle")
		var key = InputEventKey.new()
		key.keycode = KEY_C
		InputMap.action_add_event("camera_cycle", key)

func load_arena() -> void:
	# Remove existing arena
	if current_arena:
		current_arena.queue_free()
	
	# Create new arena programmatically (or load from scene)
	current_arena = SeamlessBowlArena.new()
	current_arena.name = "Arena"
	add_child(current_arena)

func spawn_player_vehicle(player_id: int, position: Vector3 = Vector3.ZERO, rotation: Vector3 = Vector3.ZERO) -> Node3D:
	# Create vehicle container
	var vehicle_container = Node3D.new()
	vehicle_container.name = "Player_%d" % player_id
	
	# Create arcade vehicle controller
	var vehicle_controller = ArcadeVehicleController.new()
	vehicle_controller.name = "ArcadeVehicleController"
	vehicle_container.add_child(vehicle_controller)
	
	# Add mesh container
	var mesh_container = Node3D.new()
	mesh_container.name = "MeshContainer"
	vehicle_controller.add_child(mesh_container)
	
	# Add camera pivot
	var camera_pivot = Node3D.new()
	camera_pivot.name = "CameraPivot"
	vehicle_controller.add_child(camera_pivot)
	
	# Add dynamic camera
	var camera = DynamicVehicleCamera.new()
	camera.name = "GameCamera"
	camera_pivot.add_child(camera)
	
	# Add spawn points (for future use)
	var spawn_points = Node3D.new()
	spawn_points.name = "SpawnPoints"
	vehicle_controller.add_child(spawn_points)
	
	# Add weapon hardpoints (for Sprint 2)
	var weapon_hardpoints = Node3D.new()
	weapon_hardpoints.name = "WeaponHardpoints"
	vehicle_controller.add_child(weapon_hardpoints)
	
	# Set initial position
	if position == Vector3.ZERO:
		position = _get_spawn_position(player_id)
	
	vehicle_controller.global_position = position
	
	# Add to scene
	add_child(vehicle_container)
	vehicles.append(vehicle_container)
	
	# Setup camera for this vehicle
	camera.set_vehicle_target(vehicle_controller)
	
	# If first player, make camera current
	if player_id == 0:
		camera.current = true
	
	return vehicle_container

func _get_spawn_position(player_id: int) -> Vector3:
	if current_arena and current_arena is SeamlessBowlArena:
		return current_arena.get_random_spawn_position()
	
	# Default spawn positions
	var spawn_positions = [
		Vector3(0, 5, 0),
		Vector3(-10, 5, 10),
		Vector3(10, 5, 10),
		Vector3(0, 5, -15)
	]
	
	return spawn_positions[player_id % spawn_positions.size()]

func _process(delta: float) -> void:
	_handle_game_state(delta)
	_check_input()

func _handle_game_state(delta: float) -> void:
	match game_state:
		GameState.LOBBY:
			# Wait for players to join
			pass
		GameState.PLAYING:
			# Update game logic
			pass
		GameState.PAUSED:
			# Game is paused
			pass
		GameState.GAME_OVER:
			# Show results
			pass

func _check_input() -> void:
	# Camera cycle
	if Input.is_action_just_pressed("camera_cycle"):
		cycle_camera()
	
	# Pause
	if Input.is_action_just_pressed("ui_cancel"):
		toggle_pause()
	
	# Reset vehicle (if stuck)
	if Input.is_key_pressed(KEY_R):
		reset_current_vehicle()

func cycle_camera() -> void:
	# Cycle through available cameras
	if cameras.size() > 1:
		for i in range(cameras.size()):
			cameras[i].current = not cameras[i].current

func toggle_pause() -> void:
	if game_state == GameState.PLAYING:
		game_state = GameState.PAUSED
		get_tree().paused = true
	elif game_state == GameState.PAUSED:
		game_state = GameState.PLAYING
		get_tree().paused = false

func reset_current_vehicle() -> void:
	if vehicles.size() > 0:
		var vehicle = vehicles[0]
		var vehicle_controller = vehicle.get_node_or_null("ArcadeVehicleController")
		if vehicle_controller:
			vehicle_controller.global_position = _get_spawn_position(0)
			vehicle_controller.rotation = Vector3.ZERO
			vehicle_controller.linear_velocity = Vector3.ZERO
			vehicle_controller.angular_velocity = Vector3.ZERO

func get_player_vehicle(player_id: int) -> Node3D:
	if player_id < vehicles.size():
		return vehicles[player_id]
	return null

func start_game() -> void:
	game_state = GameState.PLAYING

func end_game() -> void:
	game_state = GameState.GAME_OVER
