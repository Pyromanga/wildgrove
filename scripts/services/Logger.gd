extends Node

signal on_log(msg: String)

func _init() -> void:
    print("[Logger] Initialisiert (Pre-Ready)")

func log_debug(msg: String, context: String = "System") -> void:
    var time := Time.get_ticks_msec()
    var line := "[%d] [%s] %s" % [time, context, msg]
    print(line)
    on_log.emit(line)