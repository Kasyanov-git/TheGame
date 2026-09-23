extends Node3D
## Main — сборка сцены Sprint 1+2: арена, игрок (+оружие), плюшки, камера, HUD.
##
## Здесь же — «спавнер»: ставит локальную машину на SpawnPoint(0)
## (узы-заглушки арены). На Sprint 3 этот код заберёт матч-спавнер
## Colyseus, на бота — те же точки.
## Sprint 2: монтирует стартовое орудие на GunMountPoint (ТЗ п.1 — оружие
## спавнится дочерним узлом сокета). Гараж/выбор пушек — Sprint 4.


func _ready() -> void:
	var arena := get_node_or_null("Arena") as BowlArena
	var car := get_node_or_null("PlayerCar") as ArcadeVehicle
	if arena != null and car != null:
		var spawn := arena.get_spawn_point(0)
		car.respawn(spawn)
	if car != null:
		var gun_scene := load("res://src/combat/weapon_cannon.tscn") as PackedScene
		if gun_scene != null:
			car.mount_weapon(gun_scene.instantiate() as Node3D)
	get_window().title = "Overdrive Arena — Sprint 2 (WASD · Space буст · Shift дрифт · ЛКМ/F огонь · R сброс)"
