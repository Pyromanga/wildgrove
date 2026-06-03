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

func _print_log(msg: String, cat: String, level: LogLevel) -> void:
	if not enabled_levels.get(level, true):
		return
	if cat.to_lower() in _muted_categories:
		return

	var time: String    = Time.get_datetime_string_from_system(false, true)
	# FIX: Expliziter String-Typ verhindert den "cannot infer type" Fehler.
	# LogLevel.keys() gibt ein ungetyptes Array zurück — direkte Zuweisung
	# mit := lässt GDScript den Typ nicht ableiten.
	var lvl_str: String = LogLevel.keys()[level]
	var formatted: String = "[%s] [%s] [%s] %s" % [time, lvl_str, cat, msg]

	print(formatted)
	# Signal mit int statt LogLevel emittieren (kompatibel mit allen Subscribern)
	on_log.emit(formatted, cat, level as int)