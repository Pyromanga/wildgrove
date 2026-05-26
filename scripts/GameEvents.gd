extends Node

# Signale für die globale Kommunikation
signal debug_log(message: String)
signal interaction_started(label: String, duration: float)
signal interaction_finished(label: String)
signal xp_gained(skill: String, amount: int)

func log(msg: String) -> void:
	emit_signal("debug_log", msg)
	print_rich("[color=yellow][Bus][/color] ", msg)

func emit_xp(skill: String, amt: int) -> void:
	emit_signal("xp_gained", skill, amt)