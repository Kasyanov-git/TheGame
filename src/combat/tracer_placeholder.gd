class_name TracerPlaceholder
extends Node3D
## Трассер хитскана: «стержень» на ~0.07 с (п.5 ТЗ — визуальный отклик).
## Дёшево: один цилиндр без теней; на Sprint 4 заменяется шейдерной линией.

@export var lifetime := 0.07
@export var tracer_color := Color(1.0, 0.9, 0.5)

var line_from := Vector3.ZERO
var line_to := Vector3.ZERO

var _t := 0.0


func _ready() -> void:
	add_to_group("tracers")
	var len := line_from.distance_to(line_to)
	if len < 0.05:
		queue_free()
		return
	var m := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.035
	cyl.bottom_radius = 0.035
	cyl.height = len
	cyl.radial_segments = 5
	m.mesh = cyl
	m.rotation_degrees = Vector3(90.0, 0.0, 0.0)  # ось цилиндра Y -> вдоль -Z
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(tracer_color.r, tracer_color.g, tracer_color.b, 0.85)
	mat.emission_enabled = true
	mat.emission = tracer_color
	mat.emission_energy_multiplier = 2.5
	m.material_override = mat
	add_child(m)
	global_position = (line_from + line_to) * 0.5
	if len > 1e-4:
		look_at(line_to, Vector3.UP)


func _process(delta: float) -> void:
	_t += delta
	if _t >= lifetime:
		queue_free()
