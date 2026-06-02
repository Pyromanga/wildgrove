class_name Logger
extends Node

## Logger — Zentraler Logger für das gesamte Projekt.
## Erlaubt Level- und Kategorie-Filterung.
## Autoload: Logger

signal on_log(formatted: String, category: String, level: LogLevel)

enum LogLevel { DEBUG, INFO, WARN, ERROR }

## Welche Log-Level aktiv sind.
var enabled_levels: Dictionary = {
	LogLevel.DEBUG: true,
	LogLevel.INFO:  true,
	LogLevel.WARN:  true,
	LogLevel.ERROR: true,
}

## Kategorien die stummgeschaltet sind (case-insensitive).
## Nützlich um z.B. "Kernel/Topo" in Produktion zu deaktivieren.
## Beispiel: Logger.mute_category("ServiceLoader")
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

## Schaltet eine Kategorie stumm.
func mute_category(cat: String) -> void:
	var lower := cat.to_lower()
	if lower not in _muted_categories:
		_muted_categories.append(lower)

## Schaltet eine Kategorie wieder aktiv.
func unmute_category(cat: String) -> void:
	_muted_categories.erase(cat.to_lower())

## Gibt alle aktuell stummgeschalteten Kategorien zurück.
func get_muted_categories() -> Array[String]:
	return _muted_categories.duplicate()

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _print_log(msg: String, cat: String, level: LogLevel) -> void:
	if not enabled_levels.get(level, true):
		return
	if cat.to_lower() in _muted_categories:
		return

	# Datum + Uhrzeit damit Logs über Mitternacht korrekt sind
	var time    := Time.get_datetime_string_from_system(false, true)
	var lvl_str := LogLevel.keys()[level]
	var formatted := "[%s] [%s] [%s] %s" % [time, lvl_str, cat, msg]

	print(formatted)
	on_log.emit(formatted, cat, level)