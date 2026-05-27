extends Node
## GameEvents.gd — Der globale Nachrichten-Bus

signal debug_log(message: String)
signal interaction_started(label: String, duration: float)
signal interaction_finished(label: String)
signal xp_gained(skill: String, amount: int)
signal setting_changed(key: String, value: Variant)
signal state_changed(new_state: int)

func log(msg: String) -> void:
	debug_log.emit(msg)
	print_rich("[color=yellow][Bus][/color] ", msg)

func emit_xp(skill: String, amt: int) -> void:
	xp_gained.emit(skill, amt)

func emit_interaction_start(label: String, duration: float) -> void:
	interaction_started.emit(label, duration)

func emit_interaction_finished(label: String) -> void:
	interaction_finished.emit(label)