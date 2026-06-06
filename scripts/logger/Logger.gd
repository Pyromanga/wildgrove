extends Node

## Logger — Enterprise-Grade Logger für WildGrove.
##
## AutoLoad #1 — keine Abhängigkeiten, existiert für die gesamte Laufzeit.
##
## Features:
##   - 4 Log-Levels: DEBUG, INFO, WARN, ERROR
##   - Automatischer Stacktrace bei ERROR
##   - Ring-Puffer (200 Einträge) für Terminal-Replay
##   - Optionales File-Logging (user://wildgrove.log) für Blind-Coding Sessions
##   - Kategorie-basiertes Muting
##   - Strukturiertes Log-Format: [Zeit] [Level] [Kategorie] Nachricht | DATA: {...}
##   - Performance-Counter: log_count pro Level

signal on_log(formatted: String, category: String, level: int)

enum LogLevel { DEBUG, INFO, WARN, ERROR }

const MAX_BUFFER := 500  # Erhöht für lange Sessions ohne Godot-Editor
const LOG_FILE_PATH := "user://wildgrove.log"
const MAX_LOG_FILE_LINES := 5000

var enabled_levels: Dictionary = {
	LogLevel.DEBUG: true,
	LogLevel.INFO: true,
	LogLevel.WARN: true,
	LogLevel.ERROR: true,
}

var _muted_categories: Array[String] = []
var _log_buffer: Array[Dictionary] = []
var _file_logging_enabled: bool = false
var _log_file: FileAccess = null

## Performance-Counter — nützlich für Health-Checks
var log_counts: Dictionary = {
	LogLevel.DEBUG: 0,
	LogLevel.INFO: 0,
	LogLevel.WARN: 0,
	LogLevel.ERROR: 0,
}


func _ready() -> void:
	# File-Logging standardmäßig aktiv im Debug-Build
	if OS.is_debug_build():
		enable_file_logging()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_CRASH:
		_close_log_file()


# ─────────────────────────────────────────────
# Öffentliche Log-API
# ─────────────────────────────────────────────


func log_debug(msg: String, cat: String = "General") -> void:
	_print_log(msg, cat, LogLevel.DEBUG)


func log_info(msg: String, cat: String = "General") -> void:
	_print_log(msg, cat, LogLevel.INFO)


func log_warn(msg: String, cat: String = "General") -> void:
	_print_log(msg, cat, LogLevel.WARN)


func log_error(msg: String, cat: String = "General") -> void:
	_print_log(msg, cat, LogLevel.ERROR)
	push_error("[%s] %s" % [cat, msg])


## Strukturiertes Log mit zusätzlichem Daten-Dictionary.
## Format: [Zeit] [DEBUG] [Kategorie] Nachricht | DATA: {"key": "val"}
func log_trace(msg: String, data: Dictionary = {}, cat: String = "General") -> void:
	_print_log(msg, cat, LogLevel.DEBUG, data)


## Loggt den Start einer wichtigen Operation mit Timer.
## Gibt einen Timestamp zurück — übergib ihn an log_end() für die Elapsed-Zeit.
func log_begin(operation: String, cat: String = "General") -> int:
	var t := Time.get_ticks_msec()
	_print_log("▶ BEGIN: %s" % operation, cat, LogLevel.DEBUG)
	return t


## Loggt das Ende einer Operation mit Elapsed-Zeit.
func log_end(operation: String, started_at: int, cat: String = "General") -> void:
	var elapsed := Time.get_ticks_msec() - started_at
	_print_log("■ END:   %s (%d ms)" % [operation, elapsed], cat, LogLevel.DEBUG)


# ─────────────────────────────────────────────
# File-Logging
# ─────────────────────────────────────────────


func enable_file_logging() -> void:
	if _file_logging_enabled:
		return
	_log_file = FileAccess.open(LOG_FILE_PATH, FileAccess.WRITE)
	if _log_file:
		_file_logging_enabled = true
		var header := "=== WildGrove Session: %s ===" % Time.get_datetime_string_from_system()
		_log_file.store_line(header)
		print("[Logger] File-Logging aktiv: %s" % LOG_FILE_PATH)
	else:
		push_warning("[Logger] Konnte Log-Datei nicht öffnen: %s" % LOG_FILE_PATH)


func disable_file_logging() -> void:
	_close_log_file()
	_file_logging_enabled = false


# ─────────────────────────────────────────────
# Kategorie-Kontrolle
# ─────────────────────────────────────────────


func mute_category(cat: String) -> void:
	var lower := cat.to_lower()
	if lower not in _muted_categories:
		_muted_categories.append(lower)
		print("[Logger] Kategorie stummgeschaltet: '%s'" % cat)


func unmute_category(cat: String) -> void:
	_muted_categories.erase(cat.to_lower())


func get_muted_categories() -> Array[String]:
	return _muted_categories.duplicate()


# ─────────────────────────────────────────────
# Puffer-Zugriff
# ─────────────────────────────────────────────


## Gibt den Puffer zurück UND leert ihn. Für SimpleTerminal-Replay.
func flush_log_buffer() -> Array[Dictionary]:
	var copy := _log_buffer.duplicate()
	_log_buffer.clear()
	return copy


## Gibt den Puffer zurück OHNE ihn zu leeren. Für Debug-Inspektion.
func peek_log_buffer() -> Array[Dictionary]:
	return _log_buffer.duplicate()


## Gibt die Anzahl der Logs pro Level zurück.
func get_log_stats() -> Dictionary:
	return log_counts.duplicate()


## Gibt alle ERROR-Logs aus dem Puffer zurück.
func get_errors() -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	for entry in _log_buffer:
		if entry.get("level") == LogLevel.ERROR:
			errors.append(entry)
	return errors


# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────


func _print_log(msg: String, cat: String, level: int, data: Dictionary = {}) -> void:
	if not enabled_levels.get(level, true):
		return
	if cat.to_lower() in _muted_categories:
		return

	var time: String = Time.get_datetime_string_from_system(false, true)
	var level_keys: Array = LogLevel.keys()
	var lvl_str: String = (
		level_keys[level] if level >= 0 and level < level_keys.size() else "UNKNOWN"
	)

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

	# Ring-Puffer
	var entry := {"formatted": formatted, "category": cat, "level": level, "msg": msg, "data": data}
	_log_buffer.append(entry)
	if _log_buffer.size() > MAX_BUFFER:
		_log_buffer.pop_front()

	# Counter
	if log_counts.has(level):
		log_counts[level] += 1

	print(formatted)

	# File-Logging
	if _file_logging_enabled and is_instance_valid(_log_file):
		_log_file.store_line(formatted)

	on_log.emit(formatted, cat, level)


func _format_stacktrace(stack: Array) -> String:
	if stack.is_empty():
		return ""
	var lines: PackedStringArray = PackedStringArray(["Stacktrace:"])
	for frame in stack:
		var source: String = str(frame.get("source", ""))
		var function: String = str(frame.get("function", "?"))
		var line: int = int(frame.get("line", 0))
		# Logger-interne Frames überspringen
		if source.ends_with("Logger.gd") or function in ["_print_log", "log_error"]:
			continue
		lines.append("  %s:%d in %s()" % [source, line, function])
	return "\n".join(lines)


func _close_log_file() -> void:
	if is_instance_valid(_log_file):
		_log_file.flush()
		_log_file.close()
		_log_file = null
