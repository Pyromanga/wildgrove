extends Node
class_name Logger

# Logging direkt beim Laden der Engine
func _init() -> void:
	print("[Logger] Initialisiert (Pre-Ready)")

func log_debug(msg: String, context: String = "System") -> void:
	# Hier nutzen wir OS.get_ticks_msec() für echtes Timing
	var time = Time.get_ticks_msec()
	print("[%d] [%s] %s" % [time, context, msg])