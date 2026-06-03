extends Node

## SimpleTerminal — Logik-Schicht der In-Game Debug-Konsole.
## Sammelt Log-Einträge, verwaltet Befehle, toggled Sichtbarkeit.
## Die UI wird als Kind-Node separat geladen (SimpleTerminalUI).

signal entry_added(entry: LogEntry)
signal toggled(is_visible: bool)

const MAX_ENTRIES := 500

## Einzelner Log-Eintrag. Hält den bereits formatierten String.
class LogEntry:
	var formatted: String

	func _init(formatted_string: String) -> void:
		formatted = formatted_string

var entries:    Array[LogEntry] = []
var is_visible: bool = false

var _commands: Dictionary = {}

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func _init() -> void:
	pass # Hier nichts tun — zu gefährlich für Autoloads.

func _ready() -> void:
	Logger.on_log.connect(_on_log_entry)
	_register_default_commands()

	var ui_script = load("res://scripts/debug/SimpleTerminalUI.gd")
	if ui_script:
		add_child(ui_script.new())
	else:
		push_error("[SimpleTerminal] SimpleTerminalUI.gd konnte nicht geladen werden!")

	Logger.log_debug("SimpleTerminal bereit.", "Terminal")

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

func toggle() -> void:
	is_visible = !is_visible
	toggled.emit(is_visible)

func get_all_text() -> String:
	var lines := PackedStringArray()
	for e in entries:
		lines.append(e.formatted)
	return "\n".join(lines)

func execute(raw_input: String) -> void:
	var trimmed := raw_input.strip_edges()
	if trimmed.is_empty():
		return

	var parts := trimmed.split(" ", false)
	var cmd   := parts[0].to_lower()
	var args  := parts.slice(1)

	if _commands.has(cmd):
		_commands[cmd]["fn"].call(args)
	else:
		Logger.log_warn("Unbekannter Befehl: '%s'" % cmd, "Terminal")

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _on_log_entry(formatted: String, _cat: String, _level: int) -> void:
	var entry := LogEntry.new(formatted)
	entries.append(entry)
	if entries.size() > MAX_ENTRIES:
		entries.pop_front()
	entry_added.emit(entry)

func _register_default_commands() -> void:
	_commands["help"] = {
		"fn": func(_args: Array):
			var keys := _commands.keys()
			keys.sort()
			Logger.log_info("Verfügbare Befehle: %s" % str(keys), "Terminal")
	}
	_commands["clear"] = {
		"fn": func(_args: Array):
			entries.clear()
			entry_added.emit(null)
			Logger.log_debug("Terminal geleert.", "Terminal")
	}
	_commands["mute"] = {
		"fn": func(args: Array):
			if args.is_empty():
				Logger.log_warn("Verwendung: mute <kategorie>", "Terminal")
				return
			Logger.mute_category(args[0])
			Logger.log_info("Kategorie stummgeschaltet: '%s'" % args[0], "Terminal")
	}
	_commands["unmute"] = {
		"fn": func(args: Array):
			if args.is_empty():
				Logger.log_warn("Verwendung: unmute <kategorie>", "Terminal")
				return
			Logger.unmute_category(args[0])
			Logger.log_info("Kategorie reaktiviert: '%s'" % args[0], "Terminal")
	}
	_commands["muted"] = {
		"fn": func(_args: Array):
			var muted := Logger.get_muted_categories()
			if muted.is_empty():
				Logger.log_info("Keine Kategorien stummgeschaltet.", "Terminal")
			else:
				Logger.log_info("Stummgeschaltet: %s" % str(muted), "Terminal")
	}
	_commands["services"] = {
		# FIX: Kernel existiert nicht als Autoload — ersetzt durch Services-Autoload.
		# Services.world etc. sind null bis Phase 6 abgeschlossen ist,
		# deshalb prüfen wir ob der ServiceOrchestrator schon fertig ist.
		"fn": func(_args: Array):
			# Services ist immer verfügbar (Autoload #4), aber erst nach Boot befüllt.
			# Wir fragen die Registry direkt über den Orchestrator — falls verfügbar.
			var orch := get_node_or_null("/root/ServiceOrchestrator")
			if orch == null:
				Logger.log_warn("ServiceOrchestrator nicht im Baum — Services noch nicht gebootet.", "Terminal")
				return
			# FIX: War Kernel.get_registered_names() — Methode existiert nicht.
			# ServiceRegistry hat get_all_names().
			var names: Array[String] = orch.registry.get_all_names()
			names.sort()
			Logger.log_info("Registrierte Services (%d): %s" % [names.size(), str(names)], "Terminal")
	}