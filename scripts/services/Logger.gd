extends Node

signal on_log(msg: String)

func _init() -> void:
    print("[Logger] Initialisiert (Pre-Ready)")

func log_debug(msg: String, context: String = "System") -> void:
    var time := Time.get_ticks_msec()
    var line := "[%d] [%s] %s" % [time, context, msg]
    print(line)
    on_log.emit(line)

func log_error(msg: String, context: String = "System") -> void:
    var time := Time.get_ticks_msec()
    var line := "[%d] [ERROR] [%s] %s" % [time, context, msg]
    print(line)
    on_log.emit(line)

    var stack := get_stack()
    for i in stack.size():
        var frame: Dictionary = stack[i]
        var frame_line := "  #%d %s:%d @ %s()" % [
            i,
            frame.get("source", "?"),
            frame.get("line", 0),
            frame.get("function", "?")
        ]
        print(frame_line)
        on_log.emit(frame_line)