extends Node

## SimpleTerminal.gd - Logik & Command-Zentrale
## Als AutoLoad "SimpleTerminal" registrieren!
var _panel: Control
var _btn_toggle: Button
var _input: LineEdit # Für das grab_focus()

const MAX_ENTRIES := 500

signal entry_added(entry: LogEntry)
signal toggled(visible: bool)

class LogEntry:
	var timestamp: String
	var level: Logger.LogLevel
	var category: String
	var message: String
	var formatted: String

	func _init(ts: String, lvl: Logger.LogLevel, cat: String, msg: String) -> void:
		timestamp = ts
		level = lvl
		category = cat
		message = msg
		formatted = "[%s] [%s] [%s] %s" % [ts, Logger.LogLevel.keys()[lvl], cat, msg]

var entries: Array[LogEntry] = []
var is_visible: bool = false
var _commands: Dictionary = {}

func _init() -> void:
	# Verbindet sich sofort mit dem globalen Logger
	if Logger.has_signal("on_log"):
		Logger.on_log.connect(_on_log_entry)

func _ready() -> void:
	_register_default_commands()
	# Erstellt die UI automatisch als Kind von sich selbst
	var ui = SimpleTerminalUI.new()
	add_child(ui)

func _on_log_entry(msg: String, cat: String, lvl: Logger.LogLevel) -> void:
	var time = Time.get_time_string_from_system()
	var entry = LogEntry.new(time, lvl, cat, msg)
	entries.append(entry)
	
	if entries.size() > MAX_ENTRIES:
		entries.pop_front()
	
	entry_added.emit(entry)

func toggle() -> void:
	is_visible = not is_visible
	toggled.emit(is_visible)

func get_all_text() -> String:
	var lines: PackedStringArray = []
	for e in entries:
		lines.append(e.formatted)
	return "\n".join(lines)

func register_command(cmd: String, callable: Callable, description: String = "") -> void:
	_commands[cmd.to_lower()] = { "fn": callable, "desc": description }

func execute(raw_input: String) -> void:
	var trimmed = raw_input.strip_edges()
	if trimmed.is_empty(): return
	
	Logger.log_info("> " + trimmed, "CMD")
	var parts = trimmed.split(" ", false)
	var cmd = parts[0].to_lower()
	var args = parts.slice(1)

	if _commands.has(cmd):
		_commands[cmd]["fn"].call(args)
	else:
		Logger.log_warn("Unbekannter Befehl: " + cmd, "CMD")

func _register_default_commands() -> void:
	register_command("help", func(_args):
		for c in _commands:
			Logger.log_info("%-15s %s" % [c, _commands[c]["desc"]], "HELP")
	, "Zeigt alle Befehle")
	
	register_command("clear", func(_args):
		entries.clear()
		entry_added.emit(null)
	, "Leert das Terminal")

	register_command("state", func(_args):
		var gm = get_node_or_null("/root/Main/gamemanager")
		if gm and gm.has_method("get_state_name"):
			Logger.log_info("GameState: " + gm.get_state_name(), "CMD")
	, "Zeigt den GameManager-Status")
	
func _on_toggled(v: bool) -> void:
    _panel.visible = v
    # SEHR WICHTIG: Wenn zu, darf das Terminal keine Maus-Events mehr prüfen
    if v:
        _panel.mouse_filter = Control.MOUSE_FILTER_STOP
        _input.grab_focus()
    else:
        _panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    
    _btn_toggle.text = "CLOSE" if v else "LOG"