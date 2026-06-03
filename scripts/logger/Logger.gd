extends Node

## Logger — Zentraler Logger für das gesamte Projekt.
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
	# push_error spiegelt den Fehler zusätzlich im Godot-Debugger wider
	push_error("[%s] %s" % [cat, msg])

## Für tiefgehende Debug-Infos mit Daten-Snapshot
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

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _print_log(msg: String, cat: String, level: int, data: Dictionary = {}) -> void:
	# 1. Filtern
	if not enabled_levels.get(level, true): return
	if cat.to_lower() in _muted_categories: return

	# 2. Zeitstempel
	var time: String = Time.get_datetime_string_from_system(false, true)
	
	# 3. Level-String sicher auflösen (Der FIX für deinen Compiler-Fehler)
	var keys: Array = LogLevel.keys()
	var lvl_str: String = "UNKNOWN"
	if level >= 0 and level < keys.size():
		lvl_str = str(keys[level])
	
	# 4. Daten-String bauen falls vorhanden
	var data_str: String = ""
	if not data.is_empty():
		data_str = " | DATA: " + JSON.stringify(data)

	# 5. Formatierung
	var formatted: String = "[%s] [%s] [%s] %s%s" % [time, lvl_str, cat, msg, data_str]

	# 6. Ausgabe
	print(formatted)
	on_log.emit(formatted, cat, level)