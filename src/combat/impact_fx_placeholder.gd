class_name ImpactFxPlaceholder
extends Node3D
## Крошечная вспышка на месте попадания (п.5 ТЗ: «события для будущего VFX»).
## Полноценные партиклы/спрайты — Sprint 4 (арт-пайплайн); здесь — дешёвый
## unshaded-меッシュ с затуханием: headless-safe, web-совместимый.

@export var duration := 0.22
@export var flash_color := Color(1.0, 0.85, 0.4)
@export var start_scale := 0.35
@export var end_scale := 1.15

var _t := 0.0
var _mat: StandardMaterial3D


func _ready() -> void:
	var m := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 8
	sm.rings = 4
	m.mesh = sm
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = Color(flash_color.r, flash_color.g, flash_color.b, 0.9)
	_mat.emission_enabled = true
	_mat.emission = flash_color
	_mat.emission_energy_multiplier = 3.0
	m.material_override = _mat
	add_child(m)


func _process(delta: float) -> void:
	_t += delta
	var k := clampf(_t / maxf(duration, 0.01), 0.0, 1.0)
	scale = Vector3.ONE * lerpf(start_scale, end_scale, k)
	if _mat:
		var c := _mat.albedo_color
		c.a = 0.9 * (1.0 - k)
		_mat.albedo_color = c
	if _t >= duration:
		queue_free()
