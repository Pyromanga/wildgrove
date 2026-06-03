extends Node

## Logger — Zentraler Logger für das gesamte Projekt.
## Erlaubt Level- und Kategorie-Filterung.
## Autoload: Logger

signal on_log(formatted: String, category: String, level: int)

enum LogLevel { DEBUG, INFO, WARN, ERROR }

## Welche Log-Level aktiv sind.
var enabled_levels: Dictionary = {
	LogLevel.DEBUG: true,
	LogLevel.INFO:  true,
	LogLevel.WARN:  true,
	LogLevel.ERROR: true,
}

## Kategorien die stummgeschaltet sind (case-insensitive).
var _muted_categories: Array[String] = []

# ─────────────────────────────────────────────
# Öffentliche API
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

func mute_category(cat: String) -> void:
	var lower := cat.to_lower()
	if lower not in _muted_categories:
		_muted_categories.append(lower)

func unmute_category(cat: String) -> void:
	_muted_categories.erase(cat.to_lower())

func get_muted_categories() -> Array[String]:
	return _muted_categories.duplicate()

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

# res://scripts/logger/Logger.gd

# ... (enum und Variablen bleiben gleich)

## Für tiefgehende Debug-Infos mit Daten-Snapshot
func log_trace(msg: String, data: Dictionary = {}, cat: String = "General") -> void:
	if not enabled_levels.get(LogLevel.DEBUG, true): return
	_print_log(msg, cat, LogLevel.DEBUG, data)

# Wir erweitern die interne Methode um einen optionalen Data-Parameter
func _print_log(msg: String, cat: String, level: LogLevel, data: Dictionary = {}) -> void:
	if not enabled_levels.get(level, true): return
	if cat.to_lower() in _muted_categories: return

	var time := Time.get_datetime_string_from_system(false, true)
	var lvl_str := LogLevel.keys()[level]
	
	# Daten-String bauen falls vorhanden
	var data_str := ""
	if not data.is_empty():
		data_str = " | DATA: " + JSON.stringify(data)

	var formatted := "[%s] [%s] [%s] %s%s" % [time, lvl_str, cat, msg, data_str]

	print(formatted)
	on_log.emit(formatted, cat, level as int)