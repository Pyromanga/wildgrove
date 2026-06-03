# res://scripts/player/PlayerMover.gd
class_name PlayerMover
extends RefCounted

const LOG_CAT := "PlayerMover"

var _stats: PlayerData
var _modifiers: Dictionary = {} 
var _last_speed_log: float = 0.0

func _init() -> void:
	EventBus.player.speed_modifier_changed.connect(_on_mod_changed)
	EventBus.player.speed_modifier_removed.connect(_on_mod_removed)

func setup(data: PlayerData) -> void:
	_stats = data

func _on_mod_changed(id: String, multiplier: float) -> void:
	_modifiers[id] = multiplier
	Logger.log_trace("Modifikator aktiv: %s" % id, _modifiers, LOG_CAT)

func _on_mod_removed(id: String) -> void:
	_modifiers.erase(id)
	Logger.log_trace("Modifikator entfernt: %s" % id, _modifiers, LOG_CAT)

func get_current_speed() -> float:
	# Sicherheits-Check falls _stats noch nicht gesetzt ist
	if not _stats:
		return 0.0

	var final_multiplier: float = 1.0
	for m in _modifiers.values():
		final_multiplier *= m
	
	var current_speed: float = _stats.speed * final_multiplier
	
	if not is_equal_approx(current_speed, _last_speed_log):
		Logger.log_info("Speed Update: %.2f (Base: %.2f, Mult: %.2f)" % [current_speed, _stats.speed, final_multiplier], LOG_CAT)
		_last_speed_log = current_speed
		
	return current_speed

func calculate_velocity(current_vel: Vector3, direction: Vector3, delta: float, on_floor: bool) -> Vector3:
	# 1. Variable explizit typisieren (Fix für "Cannot infer type")
	var speed: float = get_current_speed()
	var target_vel: Vector3 = direction * speed
	var vel: Vector3 = current_vel
	
	# 2. FIX: Kein .get(prop, default) auf Resources!
	# Wir nutzen die Variable direkt oder prüfen auf Existenz.
	# Da PlayerData "speed" und "gravity" hat, nutzen wir sie direkt.
	# Für "accel" nutzen wir einen manuellen Fallback.
	
	var accel: float = 10.0 # Default Wert
	# Hier prüfen wir, ob die Property in der Klasse existiert (Gute Praxis bei Blind-Coding)
	if "accel" in _stats:
		accel = _stats.get("accel") # Nur EIN Argument erlaubt!

	vel.x = lerp(vel.x, target_vel.x, accel * delta)
	vel.z = lerp(vel.z, target_vel.z, accel * delta)
	
	if on_floor:
		vel.y = 0.0
	else:
		vel.y -= _stats.gravity * delta
	
	return vel