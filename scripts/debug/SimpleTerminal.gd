extends Node

## LOGIK-KLASSE
## Kümmert sich um Log-Einträge und Befehlsausführung.

const MAX_ENTRIES := 500
signal entry_added(entry: LogEntry)
signal toggled(visible: bool)

var entries: Array[LogEntry] = []
var is_visible: bool = false
var _commands: Dictionary = {}

class LogEntry:
	var formatted: String
	func _init(ts: String, lvl: int, cat: String, msg: String) -> void:
		formatted = "[%s] [%s] [%s] %s" % [ts, Logger.LogLevel.keys()[lvl], cat, msg]

func _init() -> void:
	if Logger.has_signal("on_log"):
		Logger.on_log.connect(_on_log_entry)

func _ready() -> void:
	_register_default_commands()
	# UI instanziieren
	add_child(load("res://scripts/debug/SimpleTerminalUI.gd").new())

func _on_log_entry(msg: String, cat: String, lvl: int) -> void:
	var entry = LogEntry.new(Time.get_time_string_from_system(), lvl, cat, msg)
	entries.append(entry)
	if entries.size() > MAX_ENTRIES: entries.pop_front()
	entry_added.emit(entry)

func toggle() -> void:
	is_visible = !is_visible
	toggled.emit(is_visible)

func get_all_text() -> String:
	var lines: PackedStringArray = []
	for e in entries: lines.append(e.formatted)
	return "\n".join(lines)

func execute(raw_input: String) -> void:
	var trimmed = raw_input.strip_edges()
	if trimmed.is_empty(): return
	var parts = trimmed.split(" ", false)
	var cmd = parts[0].to_lower()
	if _commands.has(cmd):
		_commands[cmd]["fn"].call(parts.slice(1))
	else:
		Logger.log_warn("Unknown cmd: " + cmd, "CMD")

func _register_default_commands() -> void:
	_commands["help"] = {"fn": func(_a): Logger.log_info("Commands: " + str(_commands.keys()), "HELP")}
	_commands["clear"] = {"fn": func(_a): entries.clear(); entry_added.emit(null)}