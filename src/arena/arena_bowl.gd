@tool
class_name BowlArena
extends Node3D
## «Seamless Bowl» — процедурная арена без углов (Sprint 1).
##
## План арены — суперэллипс («скруглённый овал», показатель > 2).
## Поперечное сечение — непрерывная цепь дуг и отрезков с C1-касательной:
##
##   плоский пол -> дуга скругления (fillet_radius) -> постоянный банковый
##   наклон (bank_deg) -> дуга доворота в вертикаль (crest_radius) ->
##   вертикальная стена (wall_height) -> губа-оверхэнг нависает внутрь
##   (lip_deg) -> короткая кромка.
##
## Ни одного угла 90° между полом и стеной: при касании машина скользит вдоль
## стены, а downforce-прижим контроллера позволяет ехать по банку как в
## Rocket League. Визуальная сетка и коллизия (ConcavePolygonShape3D) строятся
## из одной функции — рассогласования лучей подвески с геометрией нет.
##
## Физматериал по ТЗ: Friction = 0.1, Restitution = 0.3.
## Стиль: low-poly без текстур — цвет идёт вершинными красками (DoD «дешево»).
##
## @tool: `rebuild_now = true` в инспекторе пересобирает меш (итерации дизайна).
## В игре сборка происходит автоматически в _ready.

enum {
	KIND_FLOOR_EDGE = 0, ## первое кольцо, к нему «пришивается» веер пола
	KIND_BANK = 1,       ## плавный раструб (скругление)
	KIND_RAMP = 2,       ## постоянный наклон (велодром)
	KIND_CREST = 3,      ## доворот дуги в вертикаль
	KIND_WALL = 4,       ## вертикальный участок
	KIND_LIP = 5,        ## оверхэнг-губа (навес внутрь арены)
	KIND_CAP = 6,        ## короткая кромка сверху
}

@export_group("План (superellipse)")
@export var floor_a := 52.0     ## полуось X, м
@export var floor_b := 36.0     ## полуось Z, м
@export var superexp := 2.4     ## 2 = эллипс, >2 — «скруглённый прямоугольник»
@export_range(32, 512, 4) var segments := 128  ## сегментов по периметру

@export_group("Сечение (бесшовный профиль)")
@export var fillet_radius := 8.0   ## радиус скругления пол->банк (ТЗ требует min 3–5)
@export var bank_deg := 36.0       ## угол банкерного наклона
@export var ramp_length := 11.0    ## длина прямого банкерного участка
@export var crest_radius := 6.0    ## дуга, выводящая банк в вертикаль
@export var wall_height := 7.0     ## вертикальный участок стены
@export var lip_radius := 4.5      ## радиус губы-оверхэнга
@export var lip_deg := 26.0        ## насколько губа заходит внутрь (от вертикали)
@export var lip_cap := 1.2         ## горизонтальная кромка, закрывающая свод

@export_group("Материалы / стиль (low-poly, без текстур)")
@export var floor_color := Color(0.188, 0.227, 0.278)
@export var wall_color := Color(0.129, 0.161, 0.220)
@export var accent_color := Color(0.231, 0.878, 0.784)
@export var stripe_color := Color(0.906, 0.447, 0.165)
@export var physics_friction := 0.1     ## ТЗ: машина скользит вдоль стен
@export var physics_restitution := 0.3  ## ТЗ: лёгкий упругий отскок

@export_group("Editor")
@export var rebuild_now := false: set = _set_rebuild_now  ## галочка в инспекторе = пересборка


func _set_rebuild_now(v: bool) -> void:
	rebuild_now = v
	if v and Engine.is_editor_hint():
		_build()

## Статистика сборки (для отладки/скриншот-тестов)
var tri_count := 0
var wall_top_height := 0.0

var _mesh_inst: MeshInstance3D
var _static_body: StaticBody3D
## Кольца профиля: Vector4(out — сдвиг вдоль внешней нормали плана, y —
## высота, a — угол касательной, kind — сегмент профиля)
var _ring_meta: Array = []
var _rings: Array = []


func _ready() -> void:
	_build()


# ════════════════════════ план (2D-контур) ════════════════════════

## Точка контура: суперэллипс, t ∈ [0, 2π)
func _plan_point(t: float) -> Vector3:
	var c := cos(t)
	var s := sin(t)
	var x := floor_a * signf(c) * pow(absf(c), 2.0 / superexp)
	var z := floor_b * signf(s) * pow(absf(s), 2.0 / superexp)
	return Vector3(x, 0.0, z)


## Внешняя горизонтальная нормаль контура. Численно — чтобы при смене плана
## на Sprint 3 (капсула, «восьмёрка», «капля») генератор не пришлось переписывать.
func _plan_normal(t: float) -> Vector3:
	const DT := 0.001
	var d := _plan_point(t + DT) - _plan_point(t - DT)
	d.y = 0.0
	var n := Vector3(d.z, 0.0, -d.x)
	if n.length_squared() < 1e-9:
		return Vector3.RIGHT
	return n.normalized()


# ════════════════════════ профиль сечения ════════════════════════
## Строим «изломию» — массив точек (out, y, alpha, kind). Все стыки сегментов
## непрерывны по касательной: alpha на стыках совпадает, поэтому складок на
## меш-нормалях нет (C1-поверхность => DoD 2 «не влипает»).

## Push-точка профиля с дедупликацией: дуги стыкуются «в ноль» (конец одной
## совпадает с началом другой); без дедупа в сетке появляются вырожденные квады
## (два нулевых треугольника), на которых спотыкаются trimesh-билдеры
## (Jolt репортовал «Could not find a suitable initial triangle»).
func _push_point(o: float, y: float, a: float, kind: int) -> void:
	if _ring_meta.size() > 0:
		var last: Vector4 = _ring_meta[_ring_meta.size() - 1]
		if absf(last.x - o) < 1e-6 and absf(last.y - y) < 1e-6:
			return
	_ring_meta.append(Vector4(o, y, a, kind))


## Построение профиля сечения: цепь дуг и отрезков, касательная непрерывна.
func _build_profile() -> void:
	_ring_meta.clear()
	wall_top_height = 0.0
	var b := deg_to_rad(bank_deg)
	var out := 0.0
	var y := 0.0

	# 0) Кольцо у кромки плоского пола
	_push_point(0.0, 0.0, 0.0, KIND_FLOOR_EDGE)

	# 1) Дуга скругления пол -> банк: out = R*sin(u), y = R*(1-cos u)
	var n_arc := 10
	for i in range(1, n_arc + 1):
		var u := b * float(i) / float(n_arc)
		out = fillet_radius * sin(u)
		y = fillet_radius * (1.0 - cos(u))
		_push_point(out, y, u, KIND_BANK)

	# 2) Прямой банк
	var n_ramp := 4
	var out1 := fillet_radius * sin(b)
	var y1 := fillet_radius * (1.0 - cos(b))
	for i in range(1, n_ramp + 1):
		var l := ramp_length * float(i) / float(n_ramp)
		_push_point(out1 + l * cos(b), y1 + l * sin(b), b, KIND_RAMP)
	out = out1 + ramp_length * cos(b)
	y = y1 + ramp_length * sin(b)

	# 3) Дуга доворота в вертикаль (bank -> 90°)
	var out2 := out
	var y2 := y
	var n_crest := 8
	for i in range(1, n_crest + 1):
		var u2 := b + (PI * 0.5 - b) * float(i) / float(n_crest)
		out = out2 + crest_radius * (sin(u2) - sin(b))
		y = y2 + crest_radius * (cos(b) - cos(u2))
		_push_point(out, y, u2, KIND_CREST)
	var out_wall := out
	var y_wall := y  # начало вертикальной стены

	# 4) Вертикальная стена
	_push_point(out_wall, y_wall + wall_height, PI * 0.5, KIND_WALL)
	var y_top := y_wall + wall_height
	wall_top_height = y_top

	# 5) Губа-оверхэнг: дуга от вертикали внутрь (u: 90° -> 90°+lip).
	#    out(u) = out_wall + R*(sin u - 1)  (sin u < 1 => уход внутрь)
	#    y(u)   = y_top - R*cos u          (cos u < 0 => рост высоты)
	var a_lip_end := PI * 0.5 + deg_to_rad(lip_deg)
	var n_lip := 6
	for i in range(1, n_lip + 1):
		var u3 := PI * 0.5 + (a_lip_end - PI * 0.5) * float(i) / float(n_lip)
		out = out_wall + lip_radius * (sin(u3) - 1.0)
		y = y_top - lip_radius * cos(u3)
		_push_point(out, y, u3, KIND_LIP)

	# 6) Кромка свода
	out = out_wall + lip_radius * (sin(a_lip_end) - 1.0) - lip_cap
	y = y_top - lip_radius * cos(a_lip_end)
	_push_point(out, y, PI, KIND_CAP)


## Нормаль поверхности кольца: n = -plan_out*sin(a) + up*cos(a).
## a=0 (пол) -> +Y, a=90° (вертикальная стена) -> -plan_out (внутрь чаши).
func _surface_normal(plan_out: Vector3, alpha: float) -> Vector3:
	return plan_out * -sin(alpha) + Vector3.UP * cos(alpha)


func _ring_color(meta: Vector4, j: int, i: int) -> Color:
	var kind := int(meta.w)
	var a_deg := rad_to_deg(meta.z)
	var col := wall_color
	match kind:
		KIND_FLOOR_EDGE:
			col = floor_color
		KIND_BANK:
			col = floor_color.lerp(wall_color, clampf(a_deg / maxf(bank_deg, 1.0), 0.0, 1.0))
		KIND_RAMP:
			col = floor_color.lerp(wall_color, 0.85)
		KIND_LIP, KIND_CAP:
			col = accent_color if kind == KIND_LIP else accent_color.darkened(0.55)
	# Горизонтальные «слои» — каждые ~4.4 м: читается скорость по стенам
	if meta.y > 0.5 and fmod(meta.y, 4.4) < 0.16:
		col = col.darkened(0.35)
	# Вертикальные разметочные полосы на банке/стене (сектора каждые 32)
	if (kind == KIND_RAMP or kind == KIND_CREST or kind == KIND_WALL) and i % 32 < 2:
		col = stripe_color
	return col


# ════════════════════════ сборка ════════════════════════

func _build() -> void:
	_build_profile()
	var m := _ring_meta.size()
	if m < 4:
		push_error("BowlArena: профиль пуст — проверка параметров")
		return

	_ensure_children()

	# Кольца позиций
	_rings.resize(m)
	for j in range(m):
		var ring := PackedVector3Array()
		var meta: Vector4 = _ring_meta[j]
		for i in range(segments):
			var t := TAU * float(i) / float(segments)
			ring.append(_plan_point(t) + _plan_normal(t) * meta.x + Vector3(0.0, meta.y, 0.0))
		_rings[j] = ring

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col_tris := PackedVector3Array()  # коллизия: только позиции

	# — плоский пол: веер из центра
	var center := Vector3.ZERO
	for i in range(segments):
		var i2 := (i + 1) % segments
		_tri(st, col_tris, center, _rings[0][i], _rings[0][i2],
			_UPN, floor_color, _floor_color_for(i))

	# — стены/банк/губа: сетка колец
	for j in range(m - 1):
		var ma: Vector4 = _ring_meta[j]
		var mb: Vector4 = _ring_meta[j + 1]
		for i in range(segments):
			var i2 := (i + 1) % segments
			var ta := TAU * float(i) / float(segments)
			var tb := TAU * float(i2) / float(segments)
			var na := _surface_normal(_plan_normal(ta), ma.z)
			var nb := _surface_normal(_plan_normal(tb), ma.z)
			var nc := _surface_normal(_plan_normal(tb), mb.z)
			var nd := _surface_normal(_plan_normal(ta), mb.z)
			var ca := _ring_color(ma, j, i)
			var cb := _ring_color(ma, j, i2)
			var cc := _ring_color(mb, j + 1, i2)
			var cd := _ring_color(mb, j + 1, i)
			_quad(st, col_tris, _rings[j][i], _rings[j][i2], _rings[j + 1][i2], _rings[j + 1][i],
				[na, nb, nc, nd], [ca, cb, cc, cd])

	var mesh := st.commit()
	_mesh_inst.mesh = mesh
	tri_count = col_tris.size() / 3

	# — коллизия = та же геометрия (trimesh, двусторонний)
	var shape := ConcavePolygonShape3D.new()
	shape.data = col_tris
	shape.backface_collision = true  # кромка свода работает и «снизу»
	var cnode := _static_body.get_node_or_null("BowlShape") as CollisionShape3D
	if cnode == null:
		cnode = CollisionShape3D.new()
		cnode.name = "BowlShape"
		_static_body.add_child(cnode)
	cnode.shape = shape

	# — физматериал по ТЗ
	var phmat := PhysicsMaterial.new()
	phmat.friction = physics_friction
	phmat.restitution = physics_restitution
	_static_body.physics_material_override = phmat

	print("BowlArena: %d колец x %d сегм. = %d тримешей коллизии, стена %.1f м" % [
		m, segments, tri_count, wall_top_height])


const _UPN := Vector3.UP  # кеш для веера пола


func _floor_color_for(_i: int) -> Color:
	return floor_color


## Один треугольник: 3 вершины с нормалью/цветом + запись позиции в коллизию
func _tri(st: SurfaceTool, col: PackedVector3Array,
		p0: Vector3, p1: Vector3, p2: Vector3,
		n0: Vector3, c0: Color, c1: Color = Color.WHITE) -> void:
	st.set_normal(n0); st.set_color(c0); st.add_vertex(p0)
	st.set_normal(n0); st.set_color(c1); st.add_vertex(p1)
	st.set_normal(n0); st.set_color(c1); st.add_vertex(p2)
	col.append(p0); col.append(p1); col.append(p2)


## Квад из 4 углов (порядок: a,b — нижнее кольцо; c,d — верхнее)
func _quad(st: SurfaceTool, col: PackedVector3Array,
		a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		n: Array, cc: Array) -> void:
	_v(st, col, a, n[0], cc[0]); _v(st, col, b, n[1], cc[1]); _v(st, col, c, n[2], cc[2])
	_v(st, col, a, n[0], cc[0]); _v(st, col, c, n[2], cc[2]); _v(st, col, d, n[3], cc[3])


func _v(st: SurfaceTool, col: PackedVector3Array, p: Vector3, n: Vector3, c: Color) -> void:
	st.set_normal(n); st.set_color(c); st.add_vertex(p)
	col.append(p)


func _ensure_children() -> void:
	_mesh_inst = get_node_or_null("BowlMesh") as MeshInstance3D
	if _mesh_inst == null:
		_mesh_inst = MeshInstance3D.new()
		_mesh_inst.name = "BowlMesh"
		add_child(_mesh_inst)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # односторонняя «чаща» видна и снаружи
	mat.roughness = 0.92
	mat.metallic = 0.0
	_mesh_inst.material_override = mat
	_mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	_static_body = get_node_or_null("BowlBody") as StaticBody3D
	if _static_body == null:
		_static_body = StaticBody3D.new()
		_static_body.name = "BowlBody"
		_static_body.collision_layer = 1  # слой Arena
		_static_body.collision_mask = 0
		add_child(_static_body)


# ════════════════════════ API для игры ════════════════════════
## Точки спавна — узлы-заглушки из сцены (DoD 4). На Sprint 3 их читает
## спавнер матча; на Sprint 1 — respawn по кнопке R.

func get_spawn_point(index: int) -> Node3D:
	var holder := get_node_or_null("SpawnPoints")
	if holder == null or holder.get_child_count() == 0:
		return null
	return holder.get_child(index % holder.get_child_count()) as Node3D


func get_spawn_count() -> int:
	var holder := get_node_or_null("SpawnPoints")
	return holder.get_child_count() if holder else 0
