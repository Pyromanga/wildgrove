extends Node
## GameEvents.gd — Der globale Event-Bus

signal interaction_started(label: String)
signal debug_log(message: String)

func log(msg: String) -> void:
	emit_signal("debug_log", msg)
	print_rich("[color=yellow][GameEvents][/color] ", msg)