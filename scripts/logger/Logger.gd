extends Node

## Logger — Zentraler Logger für das gesamte Projekt.
## Autoload: Logger

signal on_log(formatted: String, category: String, level: int)

enum LogLevel { DEBUG, INFO, WARN, ERROR }

var enabled_levels: Dictionary = {
	LogLevel.DEBUG: true,
	LogLevel.INFO:  true,
	LogLevel.WARN:  true,
	LogLevel.ERROR: true,
}

var _muted_categories: Array[String] = []

# ---- Puffer für frühe Logs (bevor Terminal bereit ist) ----
const MAX_BUFFER := 200
var _log_buffer: Array[Dictionary] = []
# ----------------------------------------------------------

func log_debug(msg: String, cat: String = "General") -> void:
	_print_log(msg, cat, LogLevel.DEBUG)

func log_info(msg: String, cat: String = "General") -> void:
	_print_log(msg, cat, LogLevel.INFO)

func log_warn(msg: String, cat: String = "General") -> void:
	_print_log(msg, cat, LogLevel.WARN)

func log_error(msg: String, cat: String = "General") -> void:
	_print_log(msg, cat, LogLevel.ERROR)
	push_error("[%s] %s" % [cat, msg])

func log_trace(msg: String, data: Dictionary = {}, cat: String = "General") -> void:
	_print_log(msg, cat, LogLevel.DEBUG, data)

func mute_category(cat: String) -> void:
	var lower := cat.to_lower()
	if lower not in _muted_categories:
		_muted_categories.append(lower)

func unmute_category(cat: String) -> void:
	_muted_categories.erase(cat.to_lower())

func get_muted_categories() -> Array[String]:
	return _muted_categories.duplicate()

func flush_log_buffer() -> Array[Dictionary]:
	var copy := _log_buffer.duplicate()
	_log_buffer.clear()
	return copy

func _print_log(msg: String, cat: String, level: int, data: Dictionary = {}) -> void:
	if not enabled_levels.get(level, true): return
	if cat.to_lower() in _muted_categories: return

	var time: String = Time.get_datetime_string_from_system(false, true)
	var keys: Array = LogLevel.keys()
	var lvl_str: String = "UNKNOWN"
	if level >= 0 and level < keys.size():
		lvl_str = str(keys[level])

	# Automatischer Stacktrace bei ERROR
	var final_msg := msg
	if level == LogLevel.ERROR:
		var stack := _format_stacktrace(get_stack())
		if not stack.is_empty():
			final_msg += "\n" + stack

	var data_str: String = ""
	if not data.is_empty():
		data_str = " | DATA: " + JSON.stringify(data)

	var formatted: String = "[%s] [%s] [%s] %s%s" % [time, lvl_str, cat, final_msg, data_str]

	# Puffer
	var entry := {"formatted": formatted, "category": cat, "level": level}
	_log_buffer.append(entry)
	if _log_buffer.size() > MAX_BUFFER:
		_log_buffer.pop_front()

	print(formatted)
	on_log.emit(formatted, cat, level)

func _format_stacktrace(stack: Array) -> String:
	if stack.is_empty():
		return ""
	var lines: PackedStringArray = PackedStringArray(["Stacktrace:"])
	for frame in stack:
		# frame ist Dictionary, aber wir müssen die Typen sichern
		var source: String = str(frame.get("source", ""))
		var function: String = str(frame.get("function", "?"))
		var line: int = int(frame.get("line", 0))
		# Logger-interne Frames überspringen
		if source.ends_with("Logger.gd") or function == "_print_log":
			continue
		lines.append("  %s:%d in %s()" % [source, line, function])
	return "\n".join(lines)