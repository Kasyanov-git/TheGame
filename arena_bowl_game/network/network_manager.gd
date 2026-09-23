extends Node
class_name NetworkManager

## NetworkManager - Синглтон для сетевого взаимодействия с Colyseus сервером
## Обрабатывает подключение, синхронизацию состояния и интерполяцию

signal connected(room_id: String)
signal disconnected(reason: String)
signal player_joined(player_id: String)
signal player_left(player_id: String)
signal state_updated()
signal match_started()
signal match_ended(winner_id: String)

# Конфигурация
const SERVER_URL: String = "ws://localhost:2567"
const INTERPOLATION_DELAY_MS: float = 100.0
const MAX_SNAPSHOT_BUFFER: int = 60

# Состояние сети
var room: Variant = null  # Colyseus Room
var is_connected_to_server: bool = false
var local_player_id: String = ""
var snapshots: Dictionary = {}  # player_id -> Array of snapshots
var interpolated_positions: Dictionary = {}  # player_id -> Vector3
var interpolated_rotations: Dictionary = {}  # player_id -> Quaternion

# Игровые объекты для интерполяции
var remote_vehicles: Dictionary = {}  # player_id -> Vehicle node

func _ready() -> void:
	pass

func connect_to_server(server_url: String = SERVER_URL, options: Dictionary = {}) -> void:
	"""Подключение к Colyseus серверу"""
	if is_connected_to_server:
		print("Already connected to server")
		return
	
	print("Connecting to server: ", server_url)
	
	# В Godot 4.x используем WebSocket или HTTP для Colyseus
	# Для полной интеграции нужен GDNative модуль или REST API
	# Здесь реализация через HTTP long-polling как fallback
	
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_http_request_completed.bind(http_request))
	
	# Пытаемся подключиться через REST API (упрощённая версия)
	var url = server_url.replace("ws://", "http://").replace("wss://", "https://")
	url += "/matchmake/join/battle_room"
	
	var headers = ["Content-Type: application/json"]
	var json_options = JSON.stringify(options)
	
	var error = http_request.request(url, headers, HTTPClient.METHOD_POST, json_options)
	if error != OK:
		emit_signal("disconnected", "Failed to send connection request")
		http_request.queue_free()

func _on_http_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	"""Обработка ответа от сервера"""
	var http_request = get_node_or_null("HTTPRequest") as HTTPRequest
	if http_request:
		http_request.queue_free()
	
	if response_code == 200:
		var json = JSON.parse_string(body.get_string_from_utf8())
		if json and json.has("room"):
			local_player_id = json.get("sessionId", "")
			is_connected_to_server = true
			emit_signal("connected", json["room"]["roomId"])
			print("Connected! Player ID: ", local_player_id)
		else:
			emit_signal("disconnected", "Invalid response from server")
	else:
		emit_signal("disconnected", "Connection failed: %d" % response_code)

func disconnect_from_server() -> void:
	"""Отключение от сервера"""
	if room:
		room.leave()
		room = null
	
	is_connected_to_server = false
	snapshots.clear()
	emit_signal("disconnected", "Disconnected by client")

func send_input_command(throttle: float, steering: float, drift: bool, boost: bool, 
					   turret_x: float, turret_y: float, is_shooting: bool) -> void:
	"""Отправка команды управления на сервер"""
	if not is_connected_to_server or not room:
		return
	
	var command = {
		"sequenceNumber": Time.get_ticks_msec(),
		"throttle": throttle,
		"steering": steering,
		"drift": drift,
		"boost": boost,
		"turretRotationX": turret_x,
		"turretRotationY": turret_y,
		"isShooting": is_shooting,
		"timestamp": Time.get_ticks_msec()
	}
	
	# Отправляем команду (в полной версии через WebSocket)
	# room.send(command)

func receive_snapshot(snapshot_data: Dictionary) -> void:
	"""Получение снимка состояния от сервера"""
	for player_id in snapshot_data.keys():
		if player_id == local_player_id:
			continue  # Пропускаем локального игрока
		
		var snapshot = snapshot_data[player_id]
		
		if not snapshots.has(player_id):
			snapshots[player_id] = []
		
		var snapshot_array: Array = snapshots[player_id]
		snapshot_array.append({
			"timestamp": Time.get_ticks_msec(),
			"x": snapshot.get("x", 0.0),
			"y": snapshot.get("y", 0.0),
			"z": snapshot.get("z", 0.0),
			"rotX": snapshot.get("rotX", 0.0),
			"rotY": snapshot.get("rotY", 0.0),
			"rotZ": snapshot.get("rotZ", 0.0),
			"hp": snapshot.get("hp", 100),
			"isAlive": snapshot.get("isAlive", true)
		})
		
		# Ограничиваем размер буфера
		if snapshot_array.size() > MAX_SNAPSHOT_BUFFER:
			snapshot_array.pop_front()

func interpolate_remote_players(delta: float) -> void:
	"""Интерполяция позиций удалённых игроков"""
	var current_time = Time.get_ticks_msec()
	var target_time = current_time - INTERPOLATION_DELAY_MS
	
	for player_id in snapshots.keys():
		var snapshot_array: Array = snapshots[player_id]
		if snapshot_array.size() < 2:
			continue
		
		# Находим два снимка вокруг целевого времени
		var before_idx = -1
		var after_idx = -1
		
		for i in range(snapshot_array.size() - 1):
			var s1 = snapshot_array[i]
			var s2 = snapshot_array[i + 1]
			
			if s1["timestamp"] <= target_time and s2["timestamp"] >= target_time:
				before_idx = i
				after_idx = i + 1
				break
		
		if before_idx == -1 or after_idx == -1:
			continue
		
		var before = snapshot_array[before_idx]
		var after = snapshot_array[after_idx]
		
		# Вычисляем интерполяционный коэффициент
		var t = 0.0
		if after["timestamp"] != before["timestamp"]:
			t = (target_time - before["timestamp"]) / float(after["timestamp"] - before["timestamp"])
		t = clamp(t, 0.0, 1.0)
		
		# Интерполируем позицию
		var pos_before = Vector3(before["x"], before["y"], before["z"])
		var pos_after = Vector3(after["x"], after["y"], after["z"])
		var interpolated_pos = pos_before.lerp(pos_after, t)
		
		# Интерполируем вращение (только Y для начала)
		var rot_before = before["rotY"]
		var rot_after = after["rotY"]
		var interpolated_rot = lerp_angle(rot_before, rot_after, t)
		
		interpolated_positions[player_id] = interpolated_pos
		interpolated_rotations[player_id] = Quaternion.from_euler(Vector3(0, interpolated_rot, 0))
		
		# Обновляем визуальное представление
		update_remote_vehicle(player_id, interpolated_pos, interpolated_rotations[player_id], before["hp"], before["isAlive"])

func update_remote_vehicle(player_id: String, position: Vector3, rotation: Quaternion, hp: float, is_alive: bool) -> void:
	"""Обновление визуального представления удалённого игрока"""
	if not remote_vehicles.has(player_id):
		# Создаём новый vehicle для этого игрока
		create_remote_vehicle(player_id)
	
	var vehicle = remote_vehicles[player_id]
	if vehicle:
		vehicle.global_position = position
		vehicle.quaternion = rotation.slerp(vehicle.quaternion, 0.2)  # Плавное вращение
		
		# Обновляем HP бар если есть
		var health_bar = vehicle.get_node_or_null("HealthBar")
		if health_bar:
			health_bar.value = hp

func create_remote_vehicle(player_id: String) -> void:
	"""Создание визуального представления для удалённого игрока"""
	# Загружаем сцену машины (нужно настроить)
	var vehicle_scene = load("res://scenes/vehicle.tscn")
	if vehicle_scene:
		var vehicle = vehicle_scene.instantiate()
		vehicle.name = "RemotePlayer_" + player_id
		remote_vehicles[player_id] = vehicle
		
		# Добавляем в сцену (предполагается что есть узел RemotePlayers)
		var remote_players_node = get_tree().current_scene.get_node_or_null("RemotePlayers")
		if remote_players_node:
			remote_players_node.add_child(vehicle)

func remove_remote_vehicle(player_id: String) -> void:
	"""Удаление визуального представления удалённого игрока"""
	if remote_vehicles.has(player_id):
		var vehicle = remote_vehicles[player_id]
		if is_instance_valid(vehicle):
			vehicle.queue_free()
		remote_vehicles.erase(player_id)
	
	snapshots.erase(player_id)
	interpolated_positions.erase(player_id)
	interpolated_rotations.erase(player_id)

func _process(delta: float) -> void:
	"""Ежекадровое обновление интерполяции"""
	if is_connected_to_server:
		interpolate_remote_players(delta)

func get_local_player_id() -> String:
	return local_player_id

func is_multiplayer() -> bool:
	return is_connected_to_server
