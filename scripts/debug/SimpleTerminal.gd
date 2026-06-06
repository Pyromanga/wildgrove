extends Node

## SimpleTerminal — Enterprise Debug-Konsole für WildGrove.
##
## AutoLoad #3 (nach Logger, EventBus).
## Sammelt Log-Einträge, verwaltet Terminal-Befehle, zeigt/versteckt UI.
##
## PRODUCTION GUARD: Im Release-Build (OS.is_debug_build() == false) wird
## die UI nicht geladen und keine Commands registriert. Der Node existiert
## technisch (AutoLoad kann nicht bedingt geladen werden), ist aber inaktiv.
## Das verhindert Debug-Overhead in Production ohne Build-Konfigurationsänderungen.
##
## Commands:
##   help         — Liste aller Befehle
##   clear        — Terminal leeren
##   mute <cat>   — Kategorie stummschalten
##   unmute <cat> — Stummschaltung aufheben
##   muted        — Alle stummgeschalteten Kategorien anzeigen
##   services     — Alle registrierten Services auflisten
##   service <n>  — Details zu einem Service anzeigen
##   state        — GameState anzeigen
##   stats        — Logger-Statistiken anzeigen
##   errors       — Alle ERROR-Logs anzeigen
##   save         — Spielstand speichern
##   time         — Weltzeit anzeigen

signal entry_added(entry: LogEntry)
signal toggled(is_visible: bool)

const MAX_ENTRIES := 500


## Einzelner Log-Eintrag.
class LogEntry:
	var formatted: String

	func _init(formatted_string: String) -> void:
		formatted = formatted_string


var entries: Array[LogEntry] = []
var is_visible: bool = false
var _commands: Dictionary = {}

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────


func _init() -> void:
	pass  # Kein Zugriff auf Autoloads hier — zu früh.


func _ready() -> void:
	# PRODUCTION GUARD: Im Release-Build keine Debug-Infrastruktur aktivieren.
	# Log-Buffer läuft weiter (nützlich für Crash-Reports), UI und Commands nicht.
	if not OS.is_debug_build():
		Logger.log_debug("SimpleTerminal: Release-Build erkannt — UI und Commands deaktiviert.", "Terminal")
		return

	Logger.on_log.connect(_on_log_entry)
	_register_default_commands()

	# UI als Kind laden
	var ui_script = load("res://scripts/debug/SimpleTerminalUI.gd")
	if ui_script:
		add_child(ui_script.new())
	else:
		push_error("[SimpleTerminal] SimpleTerminalUI.gd nicht ladbar!")

	Logger.log_debug("SimpleTerminal bereit. Befehle: %d" % _commands.size(), "Terminal")


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
	var cmd := parts[0].to_lower()
	var args := parts.slice(1)

	if _commands.has(cmd):
		_commands[cmd]["fn"].call(args)
	else:
		Logger.log_warn("Unbekannter Befehl: '%s'. Tippe 'help'." % cmd, "Terminal")


func register_command(name: String, description: String, fn: Callable) -> void:
	_commands[name.to_lower()] = {"fn": fn, "desc": description}
	Logger.log_debug("Befehl registriert: '%s'" % name, "Terminal")


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
		"desc": "Alle verfügbaren Befehle anzeigen",
		"fn":
		func(_args: Array) -> void:
## SimpleTerminal — Enterprise Debug-Konsole für WildGrove.
##
## AutoLoad #3 (nach Logger, EventBus).
## Sammelt Log-Einträge, verwaltet Terminal-Befehle, zeigt/versteckt UI.
##
## Commands:
##   help         — Liste aller Befehle
##   clear        — Terminal leeren
##   mute <cat>   — Kategorie stummschalten
##   unmute <cat> — Stummschaltung aufheben
##   muted        — Alle stummgeschalteten Kategorien anzeigen
##   services     — Alle registrierten Services auflisten
##   service <n>  — Details zu einem Service anzeigen
##   state        — GameState anzeigen
##   stats        — Logger-Statistiken anzeigen
##   errors       — Alle ERROR-Logs anzeigen
##   save         — Spielstand speichern
##   time         — Weltzeit anzeigen

## Einzelner Log-Eintrag.

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

			# UI als Kind laden

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

			var keys := _commands.keys()
			keys.sort()
			var lines: PackedStringArray = PackedStringArray()
			for k in keys:
				var desc: String = _commands[k].get("desc", "")
				lines.append("  %-16s %s" % [k, desc])
			Logger.log_info("Befehle:\n" + "\n".join(lines), "Terminal")
	}

	_commands["clear"] = {
		"desc": "Terminal-Ausgabe leeren",
		"fn":
		func(_args: Array) -> void:
## SimpleTerminal — Enterprise Debug-Konsole für WildGrove.
##
## AutoLoad #3 (nach Logger, EventBus).
## Sammelt Log-Einträge, verwaltet Terminal-Befehle, zeigt/versteckt UI.
##
## Commands:
##   help         — Liste aller Befehle
##   clear        — Terminal leeren
##   mute <cat>   — Kategorie stummschalten
##   unmute <cat> — Stummschaltung aufheben
##   muted        — Alle stummgeschalteten Kategorien anzeigen
##   services     — Alle registrierten Services auflisten
##   service <n>  — Details zu einem Service anzeigen
##   state        — GameState anzeigen
##   stats        — Logger-Statistiken anzeigen
##   errors       — Alle ERROR-Logs anzeigen
##   save         — Spielstand speichern
##   time         — Weltzeit anzeigen

## Einzelner Log-Eintrag.

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

			# UI als Kind laden

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

			entries.clear()
			entry_added.emit(null)
			Logger.log_debug("Terminal geleert.", "Terminal")
	}

	_commands["mute"] = {
		"desc": "mute <kategorie> — Log-Kategorie stummschalten",
		"fn":
		func(args: Array) -> void:
## SimpleTerminal — Enterprise Debug-Konsole für WildGrove.
##
## AutoLoad #3 (nach Logger, EventBus).
## Sammelt Log-Einträge, verwaltet Terminal-Befehle, zeigt/versteckt UI.
##
## Commands:
##   help         — Liste aller Befehle
##   clear        — Terminal leeren
##   mute <cat>   — Kategorie stummschalten
##   unmute <cat> — Stummschaltung aufheben
##   muted        — Alle stummgeschalteten Kategorien anzeigen
##   services     — Alle registrierten Services auflisten
##   service <n>  — Details zu einem Service anzeigen
##   state        — GameState anzeigen
##   stats        — Logger-Statistiken anzeigen
##   errors       — Alle ERROR-Logs anzeigen
##   save         — Spielstand speichern
##   time         — Weltzeit anzeigen

## Einzelner Log-Eintrag.

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

			# UI als Kind laden

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

			if args.is_empty():
				Logger.log_warn("Verwendung: mute <kategorie>", "Terminal")
				return
			Logger.mute_category(args[0])
			Logger.log_info("Stummgeschaltet: '%s'" % args[0], "Terminal")
	}

	_commands["unmute"] = {
		"desc": "unmute <kategorie> — Stummschaltung aufheben",
		"fn":
		func(args: Array) -> void:
## SimpleTerminal — Enterprise Debug-Konsole für WildGrove.
##
## AutoLoad #3 (nach Logger, EventBus).
## Sammelt Log-Einträge, verwaltet Terminal-Befehle, zeigt/versteckt UI.
##
## Commands:
##   help         — Liste aller Befehle
##   clear        — Terminal leeren
##   mute <cat>   — Kategorie stummschalten
##   unmute <cat> — Stummschaltung aufheben
##   muted        — Alle stummgeschalteten Kategorien anzeigen
##   services     — Alle registrierten Services auflisten
##   service <n>  — Details zu einem Service anzeigen
##   state        — GameState anzeigen
##   stats        — Logger-Statistiken anzeigen
##   errors       — Alle ERROR-Logs anzeigen
##   save         — Spielstand speichern
##   time         — Weltzeit anzeigen

## Einzelner Log-Eintrag.

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

			# UI als Kind laden

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

			if args.is_empty():
				Logger.log_warn("Verwendung: unmute <kategorie>", "Terminal")
				return
			Logger.unmute_category(args[0])
			Logger.log_info("Reaktiviert: '%s'" % args[0], "Terminal")
	}

	_commands["muted"] = {
		"desc": "Alle stummgeschalteten Kategorien anzeigen",
		"fn":
		func(_args: Array) -> void:
## SimpleTerminal — Enterprise Debug-Konsole für WildGrove.
##
## AutoLoad #3 (nach Logger, EventBus).
## Sammelt Log-Einträge, verwaltet Terminal-Befehle, zeigt/versteckt UI.
##
## Commands:
##   help         — Liste aller Befehle
##   clear        — Terminal leeren
##   mute <cat>   — Kategorie stummschalten
##   unmute <cat> — Stummschaltung aufheben
##   muted        — Alle stummgeschalteten Kategorien anzeigen
##   services     — Alle registrierten Services auflisten
##   service <n>  — Details zu einem Service anzeigen
##   state        — GameState anzeigen
##   stats        — Logger-Statistiken anzeigen
##   errors       — Alle ERROR-Logs anzeigen
##   save         — Spielstand speichern
##   time         — Weltzeit anzeigen

## Einzelner Log-Eintrag.

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

			# UI als Kind laden

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

			var muted := Logger.get_muted_categories()
			if muted.is_empty():
				Logger.log_info("Keine Kategorien stummgeschaltet.", "Terminal")
			else:
				Logger.log_info("Stummgeschaltet: %s" % str(muted), "Terminal")
	}

	_commands["services"] = {
		"desc": "Alle registrierten Services anzeigen",
		"fn":
		func(_args: Array) -> void:
## SimpleTerminal — Enterprise Debug-Konsole für WildGrove.
##
## AutoLoad #3 (nach Logger, EventBus).
## Sammelt Log-Einträge, verwaltet Terminal-Befehle, zeigt/versteckt UI.
##
## Commands:
##   help         — Liste aller Befehle
##   clear        — Terminal leeren
##   mute <cat>   — Kategorie stummschalten
##   unmute <cat> — Stummschaltung aufheben
##   muted        — Alle stummgeschalteten Kategorien anzeigen
##   services     — Alle registrierten Services auflisten
##   service <n>  — Details zu einem Service anzeigen
##   state        — GameState anzeigen
##   stats        — Logger-Statistiken anzeigen
##   errors       — Alle ERROR-Logs anzeigen
##   save         — Spielstand speichern
##   time         — Weltzeit anzeigen

## Einzelner Log-Eintrag.

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

			# UI als Kind laden

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

			var orch := get_node_or_null("/root/ServiceOrchestrator")
			if orch == null:
				Logger.log_warn("ServiceOrchestrator nicht verfügbar.", "Terminal")
				return
			var names: Array[String] = orch.get_registered_names()
			names.sort()
			Logger.log_info("Services (%d): %s" % [names.size(), str(names)], "Terminal")
	}

	_commands["service"] = {
		"desc": "service <name> — Details zu einem Service anzeigen",
		"fn":
		func(args: Array) -> void:
## SimpleTerminal — Enterprise Debug-Konsole für WildGrove.
##
## AutoLoad #3 (nach Logger, EventBus).
## Sammelt Log-Einträge, verwaltet Terminal-Befehle, zeigt/versteckt UI.
##
## Commands:
##   help         — Liste aller Befehle
##   clear        — Terminal leeren
##   mute <cat>   — Kategorie stummschalten
##   unmute <cat> — Stummschaltung aufheben
##   muted        — Alle stummgeschalteten Kategorien anzeigen
##   services     — Alle registrierten Services auflisten
##   service <n>  — Details zu einem Service anzeigen
##   state        — GameState anzeigen
##   stats        — Logger-Statistiken anzeigen
##   errors       — Alle ERROR-Logs anzeigen
##   save         — Spielstand speichern
##   time         — Weltzeit anzeigen

## Einzelner Log-Eintrag.

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

			# UI als Kind laden

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

			if args.is_empty():
				Logger.log_warn("Verwendung: service <name>", "Terminal")
				return
			var orch := get_node_or_null("/root/ServiceOrchestrator")
			if orch == null:
				Logger.log_warn("ServiceOrchestrator nicht verfügbar.", "Terminal")
				return
			var info: Dictionary = orch.get_service_info(args[0])
			Logger.log_info("Service '%s': %s" % [args[0], JSON.stringify(info)], "Terminal")
	}

	_commands["state"] = {
		"desc": "Aktuellen GameState anzeigen",
		"fn":
		func(_args: Array) -> void:
## SimpleTerminal — Enterprise Debug-Konsole für WildGrove.
##
## AutoLoad #3 (nach Logger, EventBus).
## Sammelt Log-Einträge, verwaltet Terminal-Befehle, zeigt/versteckt UI.
##
## Commands:
##   help         — Liste aller Befehle
##   clear        — Terminal leeren
##   mute <cat>   — Kategorie stummschalten
##   unmute <cat> — Stummschaltung aufheben
##   muted        — Alle stummgeschalteten Kategorien anzeigen
##   services     — Alle registrierten Services auflisten
##   service <n>  — Details zu einem Service anzeigen
##   state        — GameState anzeigen
##   stats        — Logger-Statistiken anzeigen
##   errors       — Alle ERROR-Logs anzeigen
##   save         — Spielstand speichern
##   time         — Weltzeit anzeigen

## Einzelner Log-Eintrag.

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

			# UI als Kind laden

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

			if not is_instance_valid(Services.game_manager):
				Logger.log_warn("GameManager nicht verfügbar.", "Terminal")
				return
			var state_int := Services.game_manager.get_state()
			var state_name: String = GameEnums.State.keys()[state_int]
			Logger.log_info("GameState: %s (%d)" % [state_name, state_int], "Terminal")
	}

	_commands["stats"] = {
		"desc": "Logger-Statistiken anzeigen",
		"fn":
		func(_args: Array) -> void:
## SimpleTerminal — Enterprise Debug-Konsole für WildGrove.
##
## AutoLoad #3 (nach Logger, EventBus).
## Sammelt Log-Einträge, verwaltet Terminal-Befehle, zeigt/versteckt UI.
##
## Commands:
##   help         — Liste aller Befehle
##   clear        — Terminal leeren
##   mute <cat>   — Kategorie stummschalten
##   unmute <cat> — Stummschaltung aufheben
##   muted        — Alle stummgeschalteten Kategorien anzeigen
##   services     — Alle registrierten Services auflisten
##   service <n>  — Details zu einem Service anzeigen
##   state        — GameState anzeigen
##   stats        — Logger-Statistiken anzeigen
##   errors       — Alle ERROR-Logs anzeigen
##   save         — Spielstand speichern
##   time         — Weltzeit anzeigen

## Einzelner Log-Eintrag.

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

			# UI als Kind laden

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

			var s := Logger.get_log_stats()
			Logger.log_info(
				(
					"Logs — DEBUG: %d  INFO: %d  WARN: %d  ERROR: %d"
					% [
						s.get(Logger.LogLevel.DEBUG, 0),
						s.get(Logger.LogLevel.INFO, 0),
						s.get(Logger.LogLevel.WARN, 0),
						s.get(Logger.LogLevel.ERROR, 0)
					]
				),
				"Terminal"
			)
	}

	_commands["errors"] = {
		"desc": "Alle ERROR-Logs aus dem Puffer anzeigen",
		"fn":
		func(_args: Array) -> void:
## SimpleTerminal — Enterprise Debug-Konsole für WildGrove.
##
## AutoLoad #3 (nach Logger, EventBus).
## Sammelt Log-Einträge, verwaltet Terminal-Befehle, zeigt/versteckt UI.
##
## Commands:
##   help         — Liste aller Befehle
##   clear        — Terminal leeren
##   mute <cat>   — Kategorie stummschalten
##   unmute <cat> — Stummschaltung aufheben
##   muted        — Alle stummgeschalteten Kategorien anzeigen
##   services     — Alle registrierten Services auflisten
##   service <n>  — Details zu einem Service anzeigen
##   state        — GameState anzeigen
##   stats        — Logger-Statistiken anzeigen
##   errors       — Alle ERROR-Logs anzeigen
##   save         — Spielstand speichern
##   time         — Weltzeit anzeigen

## Einzelner Log-Eintrag.

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

			# UI als Kind laden

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

			var errs := Logger.get_errors()
			if errs.is_empty():
				Logger.log_info("Keine Fehler im Puffer.", "Terminal")
				return
			Logger.log_warn("=== %d Fehler ===" % errs.size(), "Terminal")
			for e in errs:
				Logger.log_warn(e.get("formatted", "?"), "Terminal")
	}

	_commands["save"] = {
		"desc": "Spielstand speichern",
		"fn":
		func(_args: Array) -> void:
## SimpleTerminal — Enterprise Debug-Konsole für WildGrove.
##
## AutoLoad #3 (nach Logger, EventBus).
## Sammelt Log-Einträge, verwaltet Terminal-Befehle, zeigt/versteckt UI.
##
## Commands:
##   help         — Liste aller Befehle
##   clear        — Terminal leeren
##   mute <cat>   — Kategorie stummschalten
##   unmute <cat> — Stummschaltung aufheben
##   muted        — Alle stummgeschalteten Kategorien anzeigen
##   services     — Alle registrierten Services auflisten
##   service <n>  — Details zu einem Service anzeigen
##   state        — GameState anzeigen
##   stats        — Logger-Statistiken anzeigen
##   errors       — Alle ERROR-Logs anzeigen
##   save         — Spielstand speichern
##   time         — Weltzeit anzeigen

## Einzelner Log-Eintrag.

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

			# UI als Kind laden

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

			if not is_instance_valid(Services.game_save):
				Logger.log_warn("GameSaveService nicht verfügbar.", "Terminal")
				return
			var ok := Services.game_save.save_all()
			if ok:
				Logger.log_info("Spielstand gespeichert.", "Terminal")
			else:
				Logger.log_error("Speichern fehlgeschlagen!", "Terminal")
	}

	_commands["time"] = {
		"desc": "Weltzeit anzeigen",
		"fn":
		func(_args: Array) -> void:
## SimpleTerminal — Enterprise Debug-Konsole für WildGrove.
##
## AutoLoad #3 (nach Logger, EventBus).
## Sammelt Log-Einträge, verwaltet Terminal-Befehle, zeigt/versteckt UI.
##
## Commands:
##   help         — Liste aller Befehle
##   clear        — Terminal leeren
##   mute <cat>   — Kategorie stummschalten
##   unmute <cat> — Stummschaltung aufheben
##   muted        — Alle stummgeschalteten Kategorien anzeigen
##   services     — Alle registrierten Services auflisten
##   service <n>  — Details zu einem Service anzeigen
##   state        — GameState anzeigen
##   stats        — Logger-Statistiken anzeigen
##   errors       — Alle ERROR-Logs anzeigen
##   save         — Spielstand speichern
##   time         — Weltzeit anzeigen

## Einzelner Log-Eintrag.

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

			# UI als Kind laden

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

			if not is_instance_valid(Services.world):
				Logger.log_warn("WorldService nicht verfügbar.", "Terminal")
				return
			Logger.log_info(
				"Tag %d — %s" % [Services.world.day_count, Services.world.get_formatted_time()],
				"Terminal"
			)
	}

	_commands["status"] = {
		"desc": "Service-Status-Report (alle null-Checks)",
		"fn":
		func(_args: Array) -> void:
## SimpleTerminal — Enterprise Debug-Konsole für WildGrove.
##
## AutoLoad #3 (nach Logger, EventBus).
## Sammelt Log-Einträge, verwaltet Terminal-Befehle, zeigt/versteckt UI.
##
## Commands:
##   help         — Liste aller Befehle
##   clear        — Terminal leeren
##   mute <cat>   — Kategorie stummschalten
##   unmute <cat> — Stummschaltung aufheben
##   muted        — Alle stummgeschalteten Kategorien anzeigen
##   services     — Alle registrierten Services auflisten
##   service <n>  — Details zu einem Service anzeigen
##   state        — GameState anzeigen
##   stats        — Logger-Statistiken anzeigen
##   errors       — Alle ERROR-Logs anzeigen
##   save         — Spielstand speichern
##   time         — Weltzeit anzeigen

## Einzelner Log-Eintrag.

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

			# UI als Kind laden

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

			var report := Services.get_status_report()
			var ok: Array = []
			var missing: Array = []
			for key in report:
				if report[key]:
					ok.append(key)
				else:
					missing.append(key)
			Logger.log_info("OK (%d): %s" % [ok.size(), str(ok)], "Terminal")
			if not missing.is_empty():
				Logger.log_warn("FEHLT (%d): %s" % [missing.size(), str(missing)], "Terminal")
	}
