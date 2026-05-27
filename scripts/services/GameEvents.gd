# GameEvents.gd (Service)
extends ServiceBase
class_name GameEvents

var player := PlayerEvents.new()
var world := WorldEvents.new()
var system := SystemEvents.new()

# Beispiele für die Aufteilung
class PlayerEvents:
	signal xp_gained(skill: String, amt: int)
	signal level_up(skill: String, new_lvl: int)

class WorldEvents:
	signal interaction_started(label: String, duration: float)
	signal interaction_finished(label: String)

class SystemEvents:
	signal debug_log(msg: String)
	signal setting_changed(key: String, value: Variant)