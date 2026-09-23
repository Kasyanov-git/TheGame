class_name HealthComponent
extends Node
## Модульный компонент здоровья (Sprint 2, п.3 ТЗ).
##
## Вешается на ЛЮБОЙ Node3D: машину (ArcadeVehicle) или разрушаемый объект
## (ящик/фору — на Sprint 3). Сам ничего не знает про машины:
##   * для RigidBody3D-хозяина на смерти: выключение физики (freeze),
##     снос коллизий, скрытие ноды "Visual" (если есть);
##   * хост с методом respawn_random() (ArcadeVehicle) — авто-респавн через
##     `respawn_delay` (ТЗ: 4.0 s) на случайной точке арены;
##   * free_on_death — для хлама (ящики) просто освободить узел.
##
## Сигналы (хуки под UI/VFX/неткод — DoD спринта):
##   * health_changed(new_hp, max_hp)  — полоска над машиной + HUD;
##   * on_vehicle_destroyed(vehicle, attacker_id) — кил-фид/статистика (Sprint 3);
##   * shield_changed(active) — иконка щита;
##   * revived — респавн состоялся.
##
## Щит (Pickup «Shield Bubble»): пока shield_time_left > 0, урон ПОГЛОЩАЕТСЯ
## (take_damage возвращает false, HP не меняется) — ровно ТЗ: 6 секунд.

signal health_changed(new_hp: float, max_hp: float)
signal shield_changed(active: bool)
signal on_vehicle_destroyed(vehicle: Node, attacker_id: String)
signal revived

# ─────────────────────────── Тюнинг (экспорты) ───────────────────────────
@export var max_health := 100.0            ## ТЗ: 100 HP
@export var respawn_delay := 4.0           ## ТЗ: 4.0 s до автореспауна
@export var free_on_death := false         ## ящики/декор: удалить узел вместо респавна
@export var spawn_explosion := true        ## placeholder-взрыв + force push
@export var hide_on_death := true          ## скрывать Visual-поддерево

# ─────────────────────────── Публичное состояние ───────────────────────────
var current_health := 100.0
var is_dead := false
var shield_time_left := 0.0
var last_attacker_id := ""                 ## кил-фид: кто добил

var _body: Node3D
var _respawn_pending := false
var _respawn_t := 0.0
var _saved_collision_layer := 0
var _saved_collision_mask := 0
var _shield_emitted_off := true


func _ready() -> void:
	current_health = max_health
	_body = get_parent() as Node3D
	if _body:
		_body.add_to_group("damageable")


func _physics_process(delta: float) -> void:
	# щит: тикает, на исходе — сигнал (иконка HUD)
	if shield_time_left > 0.0:
		shield_time_left = maxf(0.0, shield_time_left - delta)
		if shield_time_left <= 0.0 and not _shield_emitted_off:
			_shield_emitted_off = true
			shield_changed.emit(false)
	# таймер респавна (ТЗ: respawn_delay = 4.0 s)
	if _respawn_pending:
		_respawn_t -= delta
		if _respawn_t <= 0.0:
			_revive()


# ════════════════════════ боевой API ════════════════════════

## Урон по компоненту. Возвращает true, если HP реально изменились
## (false — щит поглотил / уже мертв / урона нет).
func take_damage(amount: float, attacker_id: String = "") -> bool:
	if is_dead or amount <= 0.0:
		return false
	if shield_time_left > 0.0:
		return false  # «Shield Bubble» поглощает урон полностью
	current_health = maxf(0.0, current_health - amount)
	last_attacker_id = attacker_id
	health_changed.emit(current_health, max_health)
	if current_health <= 0.0:
		_die(attacker_id)
	return true


func heal(amount: float) -> bool:
	if is_dead or amount <= 0.0:
		return false
	var prev := current_health
	current_health = minf(max_health, current_health + amount)
	health_changed.emit(current_health, max_health)
	return current_health > prev


## Щит на duration секунд (Sprint 2 пикап). Повторный пикап — обновляет, не складывает.
func add_shield(duration: float) -> void:
	shield_time_left = maxf(shield_time_left, duration)
	if _shield_emitted_off:
		_shield_emitted_off = false
		shield_changed.emit(true)


func is_shielded() -> bool:
	return shield_time_left > 0.0


func is_alive() -> bool:
	return not is_dead


## Полный сброс (отладка/спецрежимы).
func reset_health() -> void:
	is_dead = false
	_respawn_pending = false
	current_health = max_health
	shield_time_left = 0.0
	health_changed.emit(current_health, max_health)


# ════════════════════════ смерть / респавн ════════════════════════

func _die(attacker_id: String) -> void:
	is_dead = true
	on_vehicle_destroyed.emit(_body, attacker_id)

	if _body is RigidBody3D:
		var rb := _body as RigidBody3D
		rb.freeze = true
		rb.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		rb.linear_velocity = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO
		if rb.get_collision_layer() != 0:
			_saved_collision_layer = rb.get_collision_layer()
			_saved_collision_mask = rb.get_collision_mask()
			rb.set_collision_layer(0)
			rb.set_collision_mask(0)  # мертвый корпус не толкает снаряды/машины
	if hide_on_death:
		_set_visuals_visible(false)
	if spawn_explosion:
		_spawn_explosion()
	if free_on_death:
		queue_free()  # разрушаемый пропс
	elif _body != null and _body.has_method("respawn_random"):
		_respawn_pending = true  # машины: таймер тикает в _physics_process
		_respawn_t = respawn_delay
	else:
		_respawn_pending = false  # без точки возврата — остаётся «обломком»


func _revive() -> void:
	_respawn_pending = false
	is_dead = false
	current_health = max_health
	shield_time_left = 0.0
	if _body is RigidBody3D:
		var rb := _body as RigidBody3D
		rb.freeze = false
		rb.linear_velocity = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO
		if rb.get_collision_layer() == 0 and _saved_collision_layer != 0:
			rb.set_collision_layer(_saved_collision_layer)
			rb.set_collision_mask(_saved_collision_mask)
	_set_visuals_visible(true)
	# респавн на СЛУЧАЙНОЙ точке (ТЗ DoD 3) — хост сам знает, как телепортироваться
	if _body.has_method("respawn_random"):
		_body.call("respawn_random")
	health_changed.emit(current_health, max_health)
	revived.emit()


func _set_visuals_visible(v: bool) -> void:
	if _body == null:
		return
	var vis := _body.find_child("Visual", true, false) as Node3D
	if vis:
		vis.visible = v


func _spawn_explosion() -> void:
	## Placeholder-взрыв: вспышка-сфера + force push по машинам рядом
	## (ТЗ допускает «Placeholder Particle / Force Push на обломки»).
	var fx := preload("res://src/combat/explosion_placeholder.gd").new()
	if _body:  # до add_child глобальные сеттеры запрещены (Godot 4) — локально
		fx.position = _body.global_position + Vector3(0.0, 0.6, 0.0)
	var host: Node = get_tree().root
	if _body != null and _body.get_parent() != null:
		host = _body.get_parent()
	var excl: Array[RID] = []
	if _body is RigidBody3D:
		excl = [(_body as RigidBody3D).get_rid()]  # себя не толкаем
	fx.exclude_bodies = excl
	host.add_child(fx)
