class_name PickupBase
extends Area3D
## Плюшка на карте (Sprint 2, п.4 ТЗ): вращающийся 3D-икон + Area3D-триггер
## + таймер восстановления `cooldown = 10.0s`.
##
## Типы (по ТЗ):
##   * NITRO  — мгновенно восполняет 100% шкалы буста (через add_boost Sprint 1);
##   * REPAIR — +35 HP через HealthComponent;
##   * SHIELD — «Shield Bubble»: поглощает урон 6 с (HealthComponent.add_shield).
##
## Детекция — стандартный body_entered (площадка маленькая, машины медленные
## относительно радиуса —Area-сигналов достаточно; снарядоподобного туннелирования нет).
## На кулдауне: коллизионка выключена, иконка «гаснет» (материал darkened) —
## видно, что бонус сейчас недоступен.
##
## signal picked_up(vehicle, type) — хук UI/звук (п.5 ТЗ).

signal picked_up(vehicle: Node, pickup_type: int)

enum PickupType { REPAIR = 0, NITRO = 1, SHIELD = 2 }

const VEHICLES_LAYER := 2

@export var type: PickupType = PickupType.NITRO
@export var cooldown := 10.0            ## ТЗ: 10.0 с
@export var repair_amount := 35.0       ## ТЗ: +35 HP
@export var shield_duration := 6.0      ## ТЗ: 6 с
@export var icon_spin := 1.6            ## рад/с
@export var pickup_radius := 1.5        ## м (Area3D)
@export var pickup_height := 1.8        ## м (Area3D)

var ready_for_pickup := true

var _cd_t := 0.0
var _time := 0.0
var _icon: Node3D = null
var _shape_node: CollisionShape3D = null
var _mat_a: StandardMaterial3D = null
var _mat_b: StandardMaterial3D = null


func _ready() -> void:
	add_to_group("pickups")
	collision_layer = 16         ## слой Pickups (bit5; для отладочного просмотра)
	collision_mask = VEHICLES_LAYER
	monitoring = true
	body_entered.connect(_on_body_entered)
	_ensure_shape()
	_build_visual()
	_refresh_look()


func _process(delta: float) -> void:
	_time += delta
	if _icon != null:
		_icon.rotation.y += icon_spin * delta
		_icon.position.y = 1.15 + sin(_time * 2.3) * 0.12
	if not ready_for_pickup:
		_cd_t -= delta
		if _cd_t <= 0.0:
			_set_ready(true)


## Публичный API для спавнеров/режимов (Sprint 3: нейтральные точки захвата и т.п.)
func begin_cooldown() -> void:
	_set_ready(false)


func force_ready() -> void:
	_set_ready(true)


# ════════════════════════ подбор ════════════════════════

func _on_body_entered(body: Node) -> void:
	if not ready_for_pickup:
		return
	if body == null or not body.is_in_group("vehicles"):
		return
	var health = body.get_node_or_null("Health")
	if health != null and health.is_dead:
		return  # мёртвому не положено
	_apply_effect(body, health)
	picked_up.emit(body, int(type))
	_set_ready(false)


func _apply_effect(veh, health) -> void:
	match type:
		PickupType.REPAIR:
			if health != null:
				health.heal(repair_amount)
		PickupType.NITRO:
			if veh.has_method("add_boost"):
				veh.add_boost(veh.get("boost_capacity"))  # «мгновенно 100%»
		PickupType.SHIELD:
			if health != null:
				health.add_shield(shield_duration)


func _set_ready(v: bool) -> void:
	ready_for_pickup = v
	if not v:
		_cd_t = cooldown
	if _shape_node != null:
		_shape_node.set_deferred("disabled", not v)
	_refresh_look()


func _refresh_look() -> void:
	var strength := 1.0 if ready_for_pickup else 0.32
	var bc := _base_color().darkened(1.0 - strength)
	for m in [_mat_a, _mat_b]:
		if m != null:
			var cur := m.albedo_color
			# прозрачность (у щита альфа 0.55) сохраняем, красим RGB
			m.albedo_color = Color(bc.r, bc.g, bc.b, cur.a)
			m.emission = Color(bc.r, bc.g, bc.b)


func _base_color() -> Color:
	match type:
		PickupType.REPAIR:
			return Color(0.42, 0.92, 0.46)
		PickupType.SHIELD:
			return Color(0.62, 0.52, 1.0)
	return Color(0.32, 0.9, 1.0)  # NITRO


# ════════════════════════ визуал/коллизия (код = источник истины) ════════════════════════

func _ensure_shape() -> void:
	_shape_node = get_node_or_null("Shape") as CollisionShape3D
	if _shape_node == null:
		_shape_node = CollisionShape3D.new()
		_shape_node.name = "Shape"
		add_child(_shape_node)
	if _shape_node.shape == null:
		var cyl := CylinderShape3D.new()
		cyl.radius = pickup_radius
		cyl.height = pickup_height
		_shape_node.shape = cyl
	_shape_node.position = Vector3(0.0, pickup_height * 0.5, 0.0)


func _build_visual() -> void:
	# площадка
	var plat := MeshInstance3D.new()
	plat.name = "Platform"
	var pm := CylinderMesh.new()
	pm.top_radius = pickup_radius
	pm.bottom_radius = pickup_radius + 0.12
	pm.height = 0.1
	pm.radial_segments = 16
	plat.mesh = pm
	plat.position = Vector3(0.0, 0.05, 0.0)
	_mat_a = StandardMaterial3D.new()
	_mat_a.emission_enabled = true
	_mat_a.emission_energy_multiplier = 0.55
	plat.material_override = _mat_a
	add_child(plat)

	# иконка-«кристалл»
	_icon = Node3D.new()
	_icon.name = "Icon"
	_icon.position = Vector3(0.0, 1.15, 0.0)
	add_child(_icon)
	_mat_b = StandardMaterial3D.new()
	_mat_b.emission_enabled = true
	_mat_b.emission_energy_multiplier = 1.4
	_mat_b.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if type == PickupType.SHIELD \
			else BaseMaterial3D.TRANSPARENCY_DISABLED
	match type:
		PickupType.REPAIR:
			# «ремонтный крест» из двух боксов
			for cfg in [Vector3(1.05, 0.30, 0.30), Vector3(0.30, 1.05, 0.30)]:
				var b := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = cfg
				b.mesh = bm
				b.material_override = _mat_b
				_icon.add_child(b)
		PickupType.NITRO:
			# кольцо-«турбо»
			var t := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.42
			tm.outer_radius = 0.72
			tm.rings = 10
			tm.ring_segments = 18
			t.mesh = tm
			t.rotation_degrees = Vector3(90.0, 0.0, 0.0)
			t.material_override = _mat_b
			_icon.add_child(t)
		PickupType.SHIELD:
			# полупрозрачный «пузырь»
			var s := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.62
			sm.height = 1.24
			sm.radial_segments = 10
			sm.rings = 6
			s.mesh = sm
			var c := _base_color()
			_mat_b.albedo_color = Color(c.r, c.g, c.b, 0.55)
			s.material_override = _mat_b
			_icon.add_child(s)
	_refresh_look()
