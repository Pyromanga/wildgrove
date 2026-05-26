extends Node
## GameEvents.gd — Zentrale Signal-Schnittstelle

# Interaktion
signal interaction_started(label: String, duration: float)
signal interaction_finished(success: bool)

# Gameplay
signal xp_gained(skill: String, amount: int)
signal item_collected(item_id: String, amount: int)

# Debug
signal debug_log(message: String)

func log(msg: String) -> void:
	emit_signal("debug_log", msg)
	print("[GlobalLog] ", msg)