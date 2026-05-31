extends ServiceBase
class_name DebugConsole

## DebugConsole.gd
## Horcht auf Logger.on_log, speichert Einträge, führt Commands aus.
## Die UI (DebugConsoleUI.tscn) connected sich hier rein.

const LOG_CAT     := "DebugConsole"
const MAX_ENTRIES := 500  # Älteste Einträge werden verworfen

signal entry_added(entry: LogEntry)
signal console_toggled(visible: bool)

## Einzelner Log-Eintrag als Objekt — leichter zu filtern als Dictionaries
class LogEntry:
	var timestamp: String
	var level:     Logger.LogLevel
	var category:  String
	var message:   String
	var formatted: String

	func _init(ts: String, lvl: Logger.LogLevel, cat: String, msg: String) -> void:
		timestamp = ts
		level     = lvl
		category  = cat
		message   = msg
		formatted = "[%s] [%s] [%s] %s" % [ts, Logger.LogLevel.keys()[lvl], cat, msg]

var _entries: Array[LogEntry] = []
var _is_visible: bool = false

# Commands: String → Callable
var _commands: Dictionary = {}

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func _ready() -> void:
	Logger.log_debug("DebugConsole._ready()", LOG_CAT)
	super._ready()

func init() -> void:
	super.init()
	Logger.log_debug("init() — verbinde Logger.on_log Signal...", LOG_CAT)
	# Logger.on_log sendet (message, category, level) — wir fangen alles ab
	Logger.on_log.connect(_on_log_entry)
	Logger.log_debug("Logger.on_log verbunden.", LOG_CAT)
	_register_default_commands()

func on_ready() -> void:
	super.on_ready()
	Logger.log_debug("on_ready() — DebugConsole bereit.", LOG_CAT)

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

## Gibt alle gespeicherten Einträge zurück, optional gefiltert.
func get_entries(
	filter_level: Logger.LogLevel = Logger.LogLevel.DEBUG,
	filter_category: String = ""
) -> Array[LogEntry]:
	Logger.log_debug("get_entries(level=%s, cat='%s')" % [Logger.LogLevel.keys()[filter_level], filter_category], LOG_CAT)
	var result: Array[LogEntry] = []
	for entry in _entries:
		if entry.level < filter_level:
			continue
		if filter_category != "" and not entry.category.begins_with(filter_category):
			continue
		result.append(entry)
	Logger.log_debug("get_entries() → %d Einträge zurückgegeben." % result.size(), LOG_CAT)
	return result

## Alle Einträge als einzelner String — für Copy-Button.
func get_all_as_text(filter_level: Logger.LogLevel = Logger.LogLevel.DEBUG, filter_category: String = "") -> String:
	var lines: PackedStringArray = []
	for entry in get_entries(filter_level, filter_category):
		lines.append(entry.formatted)
	return "\n".join(lines)

## Console ein-/ausblenden — UI horcht auf console_toggled Signal.
func toggle() -> void:
	_is_visible = not _is_visible
	Logger.log_debug("Console toggled → %s" % str(_is_visible), LOG_CAT)
	console_toggled.emit(_is_visible)

func is_visible_console() -> bool:
	return _is_visible

## Command registrieren. callable bekommt Array[String] als Argumente.
## Beispiel: register_command("heal", func(args): player.heal(100))
func register_command(cmd: String, callable: Callable, description: String = "") -> void:
	Logger.log_debug("Command registriert: '%s' — %s" % [cmd, description], LOG_CAT)
	_commands[cmd.to_lower()] = { "fn": callable, "desc": description }

## Command ausführen. Input ist der rohe String aus dem Textfeld.
func execute(raw_input: String) -> void:
	var trimmed := raw_input.strip_edges()
	if trimmed.is_empty():
		return

	Logger.log_info("> %s" % trimmed, LOG_CAT)

	var parts := trimmed.split(" ", false)
	var cmd   := parts[0].to_lower()
	var args  := parts.slice(1)

	if not _commands.has(cmd):
		Logger.log_warn("Unbekannter Command: '%s'. 'help' für Liste." % cmd, LOG_CAT)
		return

	Logger.log_debug("Führe Command aus: '%s' mit Args: %s" % [cmd, str(args)], LOG_CAT)
	_commands[cmd]["fn"].call(args)

func get_command_list() -> Array[String]:
	var list: Array[String] = []
	for cmd in _commands:
		var desc: String = _commands[cmd]["desc"]
		list.append("%-20s %s" % [cmd, desc])
	return list

# ─────────────────────────────────────────────
# Private
# ─────────────────────────────────────────────

func _on_log_entry(message: String, category: String, level: Logger.LogLevel) -> void:
	var time   := Time.get_time_string_from_system()
	var entry  := LogEntry.new(time, level, category, message)
	_entries.append(entry)

	if _entries.size() > MAX_ENTRIES:
		_entries.pop_front()

	entry_added.emit(entry)

func _register_default_commands() -> void:
	Logger.log_debug("Registriere Default-Commands...", LOG_CAT)

	register_command("help", func(_args):
		for line in get_command_list():
			Logger.log_info(line, "CMD")
	, "Zeigt alle verfügbaren Commands")

	register_command("clear", func(_args):
		_entries.clear()
		Logger.log_info("Console geleert.", "CMD")
	, "Leert die Console")

	register_command("services", func(_args):
		for svc_name in Kernel.services:
			Logger.log_info("  • %s" % svc_name, "CMD")
	, "Listet alle registrierten Services")

	register_command("state", func(_args):
		var gm := Kernel.get_service("gamemanager") as GameManager
		if gm:
			Logger.log_info("GameState: %s" % gm.get_state_name(), "CMD")
		else:
			Logger.log_warn("GameManager nicht gefunden.", "CMD")
	, "Zeigt den aktuellen GameState")

	register_command("save", func(_args):
		var gm := Kernel.get_service("gamemanager") as GameManager
		if gm:
			gm.save_game({})
		else:
			Logger.log_warn("GameManager nicht gefunden.", "CMD")
	, "Speichert das Spiel")

	Logger.log_debug("Default-Commands registriert: %d Stück." % _commands.size(), LOG_CAT)
