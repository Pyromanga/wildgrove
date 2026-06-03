extends Node3D
## World.gd — Einstiegspunkt der Spielwelt.
##
## _ready() feuert garantiert erst nachdem der Node vollständig im SceneTree ist —
## deshalb triggern wir die prozedurale Welt-Erzeugung von hier aus, statt
## über ein call_deferred im WorldService (welches zu früh feuerte).


func _ready() -> void:
	Logger.log_debug("World-Szene betreten.", "World")

	if not is_instance_valid(Services.world):
		Logger.log_error(
			"WorldService nicht verfügbar – Welt kann nicht initialisiert werden.", "World"
		)
		return

	Services.world.on_world_scene_ready(self)
