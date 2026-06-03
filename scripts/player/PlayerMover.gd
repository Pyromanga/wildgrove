# res://scripts/player/PlayerMover.gd
class_name PlayerMover
extends RefCounted

const LOG_CAT := "PlayerMover"

var _stats: PlayerData
var _modifiers: Dictionary = {} # Speichert "ID": Multiplier (z.B. "sprint": 1.5)
var _last_speed_log: float = 0.0

func _init() -> void:
	# Wir verbinden uns direkt mit dem EventBus
	EventBus.player.speed_modifier_changed.connect(_on_mod_changed)
	EventBus.player.speed_modifier_removed.connect(_on_mod_removed)

func setup(data: PlayerData) -> void:
	_stats = data

func _on_mod_changed(id: String, multiplier: float) -> void:
	_modifiers[id] = multiplier
	Logger.log_trace("Modifikator aktiv", _modifiers, LOG_CAT)

func _on_mod_removed(id: String) -> void:
	_modifiers.erase(id)
	Logger.log_trace("Modifikator entfernt: " + id, _modifiers, LOG_CAT)

## Berechnet den aktuellen Speed unter Berücksichtigung aller Mods
func get_current_speed() -> float:
	var final_multiplier := 1.0
	for m in _modifiers.values():
		final_multiplier *= m
	
	var current_speed = _stats.speed * final_multiplier
	
	# Exzessives Logging bei Änderung
	if not is_equal_approx(current_speed, _last_speed_log):
		Logger.log_info("Dynamische Geschwindigkeit: %.2f (Basis: %.2f, Multi: %.2f)" % [current_speed, _stats.speed, final_multiplier], LOG_CAT)
		_last_speed_log = current_speed
		
	return current_speed

func calculate_velocity(current_vel: Vector3, direction: Vector3, delta: float, on_floor: bool) -> Vector3:
	var speed = get_current_speed() # <--- Hier nutzen wir den dynamischen Wert
	var target_vel := direction * speed
	var vel        := current_vel
	
	# Hier nutzen wir auch stats aus der .tres (accel, gravity)
	vel.x = lerp(vel.x, target_vel.x, _stats.get("accel", 10.0) * delta)
	vel.z = lerp(vel.z, target_vel.z, _stats.get("accel", 10.0) * delta)
	vel.y = 0.0 if on_floor else vel.y - _stats.gravity * delta
	
	return vel