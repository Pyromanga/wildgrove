extends Node

## Zentraler Logger für das gesamte Projekt.
## Erlaubt Kategorisierung und später das Filtern in der Dev-Konsole.

signal on_log(message: String, category: String, level: LogLevel)

enum LogLevel { DEBUG, INFO, WARN, ERROR }

func log_debug(msg: String, cat: String = "General") -> void:
	_print_log(msg, cat, LogLevel.DEBUG)

func log_info(msg: String, cat: String = "General") -> void:
	_print_log(msg, cat, LogLevel.INFO)

func log_warn(msg: String, cat: String = "General") -> void:
	_print_log(msg, cat, LogLevel.WARN)

func log_error(msg: String, cat: String = "General") -> void:
	_print_log(msg, cat, LogLevel.ERROR)
	push_error("[%s] %s" % [cat, msg])

func _print_log(msg: String, cat: String, level: LogLevel) -> void:
	var time = Time.get_time_string_from_system()
	var level_name = LogLevel.keys()[level]
	var formatted = "[%s] [%s] [%s] %s" % [time, level_name, cat, msg]
	
	# In Standard-Konsole ausgeben
	print(formatted)
	
	# Signal für In-Game Konsole
	on_log.emit(formatted, cat, level)