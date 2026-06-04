# res://scripts/player/PlayerMover.gd
class_name PlayerMover
extends RefCounted

const LOG_CAT := "PlayerMover"

## Direkt gesetzte Stats (von Player._apply_stats() via Services.data).
## _stats (PlayerData-Resource) wird nicht mehr benötigt — DataService ist
## die Single Source of Truth, Player injiziert die Werte als floats.
var speed: float = 6.0
var gravity: float = 12.0

var _modifiers: Dictionary = {}
var _last_speed_log: float = 0.0


func _init() -> void:
	EventBus.player.speed_modifier_changed.connect(_on_mod_changed)
	EventBus.player.speed_modifier_removed.connect(_on_mod_removed)


func _on_mod_changed(id: String, multiplier: float) -> void:
	_modifiers[id] = multiplier
	Logger.log_trace("Modifikator aktiv: %s" % id, _modifiers, LOG_CAT)


func _on_mod_removed(id: String) -> void:
	_modifiers.erase(id)
	Logger.log_trace("Modifikator entfernt: %s" % id, _modifiers, LOG_CAT)


func get_current_speed() -> float:
	var final_multiplier: float = 1.0
	for m in _modifiers.values():
		final_multiplier *= m

	var current_speed: float = speed * final_multiplier

	if not is_equal_approx(current_speed, _last_speed_log):
		Logger.log_info(
			"Speed Update: %.2f (Base: %.2f, Mult: %.2f)" % [current_speed, speed, final_multiplier],
			LOG_CAT
		)
		_last_speed_log = current_speed

	return current_speed


func calculate_velocity(
	current_vel: Vector3, direction: Vector3, delta: float, on_floor: bool
) -> Vector3:
	var effective_speed: float = get_current_speed()
	var target_vel: Vector3 = direction * effective_speed
	var vel: Vector3 = current_vel

	# Accel ist kein exportierter Stat (nicht in PlayerData.tres), daher Konstante.
	# Wenn er konfigurierbar werden soll: in PlayerData.gd als @export ergänzen
	# und hier über Player._apply_stats() injizieren — analog zu speed/gravity.
	const ACCEL: float = 10.0

	vel.x = lerp(vel.x, target_vel.x, ACCEL * delta)
	vel.z = lerp(vel.z, target_vel.z, ACCEL * delta)

	if on_floor:
		vel.y = 0.0
	else:
		vel.y -= gravity * delta
		Logger.log_trace(
			"Gravity angewandt: vel.y=%.3f (gravity=%.1f)" % [vel.y, gravity], {}, LOG_CAT
		)

	return vel
