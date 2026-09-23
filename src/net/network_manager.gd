extends Node
## NetworkManager — синглтон-сервис клиента (Sprint 3, ТЗ п.4).
##
## Подключение к боевому серверу через Godot-relay (JSON over WebSocket;
## relay внутри сервера держит для клиента полноценную Colyseus-комнату
## BattleRoom: та же авторитарная симуляция, snapshots, hit validation, боты).
##
## Сетевая модель (ТЗ п.2):
##  * локальная машина — Client-Side Prediction: вся физика считается здесь,
##    UserCommand (throttle/steering/drift/turret/isShooting/sequenceNumber
##    + самоотчёт позиции) уходит на сервер 30 Гц;
##  * чужие машины — NetAvatar: интерполяция снапшотов с буфером ~100 мс
##    (lerp позиции + slerp кватерниона поворота);
##  * HP/урон/смерть/пикапы — решает сервер, клиент реплицирует snapshot'ом.
##
## Запуск: аргумент `--net` (дефолтный URL) или `--net=ws://host:2567/godot-relay`.
## Без аргумента — offline (solo-режим Sprint 2 не меняется).

const RELAY_DEFAULT_URL := "ws://127.0.0.1:2567/godot-relay"
const INPUT_HZ := 30.0                  ## ТЗ: 30–60 Гц
const RUBBER_BAND_DIST := 4.0           ## м — «сервер тянет клиента назад»
const CAR_SCENE := preload("res://src/vehicle/player_car.tscn")
const PROJ_SCENE := preload("res://src/combat/projectile.tscn")
const NET_AVATAR := preload("res://src/net/net_avatar.gd")

signal onJoin(id)
signal onLeave(id)
signal onStateChange(snapshot)
signal onPlayerAdd(id)
signal onPlayerRemove(id)
signal net_status(text)

var active := false
var local_sid := ""
var url := RELAY_DEFAULT_URL
var status_line := "offline"

# WebSocketPeer создаётся через ClassDB: headless/wasm-сборки могут быть
# собраны без модуля websocket — там сеть просто недоступна (offline),
# а юнит-путь (feed_snapshot/интерполяция) остаётся рабочим.
const WS_OPEN := 1     # WebSocketPeer.ConnectionState.CONNECTION_OPEN
const WS_CLOSED := 2  # …CONNECTION_CLOSED
var _peer: Object = null
var _want_join := false
var _seq := 0
var _input_acc := 0.0
var _car: Node = null
var _host: Node = null
var _snap: Dictionary = {}
var _avatars: Dictionary = {}
var _known := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--net"):
			var eq := s.find("=")
			join(s.substr(eq + 1) if eq != -1 else RELAY_DEFAULT_URL)
			return


func _ws_status() -> int:
	return -1 if _peer == null else int(_peer.call("get_connection_status"))


func join(p_url: String) -> void:
	url = p_url
	_peer = ClassDB.instantiate("WebSocketPeer")
	if _peer == null:
		status_line = "no websocket module"
		net_status.emit(status_line)
		return
	var err: int = int(_peer.call("connect_to_url", url))
	if err != OK:
		status_line = "connect failed"
		net_status.emit(status_line)
		return
	_want_join = true
	status_line = "connecting…"


## main.gd после сборки сцены. bind безопасен и до join().
func bind(car: Node, host: Node) -> void:
	_car = car
	_host = host
	if active:
		_setup_net_world()


func is_online() -> bool:
	return active


func snapshot() -> Dictionary:
	return _snap


func leave() -> void:
	if _ws_status() == WS_OPEN:
		_peer.call("close")
	active = false
	for id in _avatars.keys():
		_despawn_avatar(id)
	_known.clear()


func _physics_process(delta: float) -> void:
	_poll_ws()
	if _want_join and not active and _ws_status() == WS_OPEN:
		_want_join = false
		active = true
		status_line = "online"
		net_status.emit("online: " + url)
		_setup_net_world()
	if _ws_status() == WS_CLOSED and (active or _want_join):
		active = false
		_want_join = false
		status_line = "closed"
		net_status.emit("connection closed")
	if not active or _car == null:
		return
	_input_acc += delta
	var step := 1.0 / INPUT_HZ
	while _input_acc >= step:
		_input_acc -= step
		_seq += 1
		if _ws_status() == WS_OPEN:
			_peer.call("send_text", JSON.stringify(_pack_input(_seq)))


func _process(_delta: float) -> void:
	_poll_ws()


func _poll_ws() -> void:
	if _peer == null:
		return
	_peer.call("poll")
	while int(_peer.call("get_available_packet_count")) > 0:
		var pkt: PackedByteArray = _peer.call("get_packet")
		var m = JSON.parse_string(pkt.get_string_from_utf8())
		if typeof(m) == TYPE_DICTIONARY:
			_on_message(m)


# ── исходящие ─────────────────────────────────────────────────────

## UserCommand (ТЗ п.2): throttle, steering, drift, turretRotation, isShooting,
## sequenceNumber — плюс самоотчёт предсказанной позиции (px/pz/ry/vx/vz),
## который сервер валидирует и принимает как авторитет (trust-but-verify).
func _pack_input(seq: int) -> Dictionary:
	var throttle: float = Input.get_action_strength("throttle") - Input.get_action_strength("brake")
	var steer: float = Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	var angles := _aim_angles()
	var vel: Vector3 = _car.linear_velocity if "linear_velocity" in _car else Vector3.ZERO
	return {
		"t": "in", "s": seq,
		"th": throttle, "st": steer,
		"dr": 1 if Input.is_action_pressed("drift") else 0,
		"bo": 1 if Input.is_action_pressed("boost") else 0,
		"f": 1 if Input.is_action_pressed("fire") else 0,
		"ay": angles[0], "ap": angles[1],
		"px": _car.global_position.x, "pz": _car.global_position.z,
		"ry": _car.rotation.y,
		"vx": vel.x, "vz": vel.z,
	}


## yaw/pitch прицела: луч камеры в центр экрана (тот же crosshair-ray, что у
## TurretAimer). Headless/вырожденный viewport — курс машины.
func _aim_angles() -> Array:
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp != null else null
	var dir := Vector3.ZERO
	if cam != null and vp != null and vp.get_visible_rect().size.y > 1.0:
		var center: Vector2 = vp.get_visible_rect().size * 0.5
		dir = cam.project_ray_normal(center)
	if dir.length_squared() < 1e-6:
		var f := -_car.global_transform.basis.z
		f.y = 0.0
		dir = f if f.length_squared() > 1e-9 else Vector3.BACK
	return [atan2(-dir.x, -dir.z), asin(clampf(dir.y, -1.0, 1.0))]


# ── входящие ───────────────────────────────────────────────────────

func _on_message(m: Dictionary) -> void:
	match String(m.get("t", "")):
		"ok":
			local_sid = String(m.get("id", ""))
			status_line = "sid " + local_sid.left(6)
			net_status.emit(status_line)
			onJoin.emit(local_sid)
		"st":
			_feed_snapshot(m)
		"ev":
			_on_event(m)
		"rec":
			_rubber_band(m)
		"err":
			status_line = "error: " + String(m.get("m", "?"))
			net_status.emit(status_line)


func _feed_snapshot(s: Dictionary) -> void:
	_snap = s
	onStateChange.emit(s)
	var rows: Array = s.get("pl", [])
	var seen := {}
	for row in rows:
		var id := String(row[0])
		if id == local_sid:
			continue
		seen[id] = true
		if not _known.has(id):
			_known[id] = true
			_spawn_avatar(id)
			onPlayerAdd.emit(id)
		var av = _avatars.get(id)
		if av != null:
			# [id, x, z, rotY, hp, score, bot, mg, shT, boT, aimYaw, aimPitch, vx, vz]
			av.push_key(Vector3(float(row[1]), 1.19, float(row[2])),
				float(row[3]), float(row[10]), float(row[11]), float(row[4]))
	for id in _known.keys():
		if not seen.has(id):
			_known.erase(id)
			_despawn_avatar(id)
			onPlayerRemove.emit(id)
			onLeave.emit(id)
	# pick-up кулдауны сервера: pk = [[idx, type, x, z, cd], …]
	var nodes := get_tree().get_nodes_in_group("pickups")
	for pk in s.get("pk", []):
		var idx := int(pk[0])
		if idx >= 0 and idx < nodes.size():
			nodes[idx].call("set_net_cd", float(pk[4]))
	# свой hp — серверный факт
	for row in rows:
		if String(row[0]) == local_sid and _car != null:
			var h = _car.get_node_or_null("Health")
			if h != null:
				h.call("set_net_hp", float(row[4]))
				h.call("set_net_shield", float(row[8]))
			break


func _setup_net_world() -> void:
	if _car == null:
		return
	# локальные симуляции переключаются в сетевой режим: урон/щит/пикапы
	# решает сервер, клиент только реплицирует
	var h = _car.get_node_or_null("Health")
	if h != null:
		h.set("net_mode", true)
	for node in get_tree().get_nodes_in_group("pickups"):
		node.set("net_mode", true)


# ── аватары чужих машин ───────────────────────────────────────────

func _spawn_avatar(id: String) -> void:
	if _host == null or _avatars.has(id):
		return
	var av: Node3D = NET_AVATAR.new()
	av.setup(id)
	var v = CAR_SCENE.instantiate()
	v.control_enabled = false
	v.freeze = true
	v.collision_layer = 0
	v.collision_mask = 0
	var h = v.get_node_or_null("Health")
	if h != null:
		h.set("net_mode", true)
	av.add_child(v)
	av.vehicle = v
	_host.add_child(av)
	_avatars[id] = av


func _despawn_avatar(id: String) -> void:
	if _avatars.has(id):
		_avatars[id].queue_free()
		_avatars.erase(id)


# ── rubber-band / события ─────────────────────────────────────────

func _rubber_band(m: Dictionary) -> void:
	## rec = {x, z, rotY}: сервер отверг самоотчёт (слишком быстрая/невозможная
	## метка). Мягкое возвращение: >RUBBER_BAND_DIST — мгновенный перенос,
	## меньше — доверяем предсказанию клиента.
	if _car == null:
		return
	var target := Vector3(float(m.get("x", 0.0)), _car.global_position.y, float(m.get("z", 0.0)))
	if target.distance_squared_to(_car.global_position) > RUBBER_BAND_DIST * RUBBER_BAND_DIST:
		if _car.has_method("teleport_net"):
			_car.call("teleport_net", target, float(m.get("rotY", _car.rotation.y)))


func _on_event(m: Dictionary) -> void:
	match String(m.get("e", "")):
		"fire":
			if String(m.get("a", {}).get("id", "")) != local_sid:
				_spawn_cosmetic_shot(m.get("a", {}))
		"hit":
			var a: Dictionary = m.get("a", {})
			var av = _avatars.get(String(a.get("id", "")))
			if av != null:
				av.set_meta("hit_flash", 0.25)
		"pickup":
			pass   # вид пикапа синхронизируется снапшотом (cd)
		"start", "spawn", "death", "kill", "finished":
			pass   # hp/позиции — через снапшоты; HUD читает _snap


## Визуальный снаряд чужого выстрела (урон авторизует сервер — этот декоративный,
## source=null => никому не наносит урона).
func _spawn_cosmetic_shot(a: Dictionary) -> void:
	if _host == null:
		return
	var yaw := float(a.get("yaw", 0.0))
	var pitch := float(a.get("pitch", 0.0))
	var dir := Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
	var pos := Vector3(float(a.get("x", 0.0)), float(a.get("y", 1.19)) + 0.75, float(a.get("z", 0.0)))
	pos += Vector3(-sin(yaw), 0.0, -cos(yaw)) * 2.1
	var pr = PROJ_SCENE.instantiate()
	pr.setup(pos, dir, 120.0, 0.0, 3.0, null, null)
	_host.add_child(pr)
