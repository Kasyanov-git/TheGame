extends Node3D
## Main — сборка сцены Sprint 1: арена, игрок, камера, HUD.
##
## Здесь же — «спавнер»: ставит локальную машину на SpawnPoint(0)
## (узы-заглушки арены). На Sprint 3 этот код заберёт матч-спавнер
## Colyseus, на бота — те же точки.


func _ready() -> void:
	var arena := get_node_or_null("Arena") as BowlArena
	var car := get_node_or_null("PlayerCar") as ArcadeVehicle
	if arena != null and car != null:
		var spawn := arena.get_spawn_point(0)
		car.respawn(spawn)
	get_window().title = "Overdrive Arena — Sprint 1 (WASD · Space буст · Shift дрифт · R сброс)"
