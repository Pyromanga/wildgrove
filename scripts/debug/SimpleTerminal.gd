extends Node

## SimpleTerminal — Debug-Konsole.
##
## AutoLoad #3 (nach AppLogger, EventBus).
## Im Release-Build (OS.is_debug_build() == false): UI + Commands deaktiviert.
##
## Befehle: help, clear, mute, unmute, muted, services, service,
##           state, stats, errors, save, time, status, loglevel, respawns,
##           mem, memhistory, pool

signal entry_added(entry: LogEntry)
signal toggled(is_visible: bool)

const MAX_ENTRIES := 4000

class LogEntry:
	var formatted: String
	func _init(s: String) -> void:
		formatted = s

var entries: Array[LogEntry] = []
var is_visible: bool = false
var _commands: Dictionary = {}

func _ready() -> void:
	if not OS.is_debug_build():
		return
	AppLogger.on_log.connect(_on_log_entry)
	_register_default_commands()
	AdminMenuCommands.new(self)  # Admin-Menü: gold/item/speed/heal/role/kick/tp usw.
	# SimpleTerminalUI direkt instanziieren — class_name ist global verfügbar.
	# load() + .new() war fragil wenn der Pfad zur Laufzeit nicht auflösbar war.
	var ui := SimpleTerminalUI.new()
	add_child(ui)
	# Wunsch "Admin-Commands nicht mehr per Hand eintippen müssen" — Button-UI
	# über denselben execute()-Pfad wie die Terminal-Texteingabe (siehe
	# AdminPanelUI.gd Klassenkommentar). NACH AdminMenuCommands.new() oben,
	# damit alle Commands schon registriert sind.
	var admin_ui := AdminPanelUI.new()
	add_child(admin_ui)
	AppLogger.log_debug("SimpleTerminal bereit. Befehle: %d" % _commands.size(), "Terminal")

func toggle() -> void:
	is_visible = !is_visible
	toggled.emit(is_visible)

func get_all_text() -> String:
	var lines := PackedStringArray()
	for e in entries:
		lines.append(e.formatted)
	return "\n".join(lines)

## Schreibt den kompletten aktuellen Puffer als eigene Datei nach user://.
## Umgeht OS-seitige Clipboard-Größenlimits (v.a. auf Mobile), die dazu führen
## können dass DisplayServer.clipboard_set() lange Texte klammheimlich kürzt —
## COPY ALL sah dadurch "abgeschnitten" aus, obwohl entries/get_all_text() schon
## vollständig waren. Diese Datei ist die zuverlässige Quelle für lange Logs.
func export_all_text_to_file() -> String:
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	var path := "user://terminal_export_%s.log" % stamp
	var f := FileAccess.open(path, FileAccess.WRITE)
	if not f:
		AppLogger.log_warn("Konnte Export-Datei nicht öffnen: %s" % path, "Terminal")
		return ""
	f.store_string(get_all_text())
	f.close()
	return path

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
		AppLogger.log_warn("Unbekannter Befehl: '%s'. Tippe 'help'." % cmd, "Terminal")

func register_command(name: String, description: String, fn: Callable) -> void:
	_commands[name.to_lower()] = {"fn": fn, "desc": description}
	AppLogger.log_debug("Befehl registriert: '%s'" % name, "Terminal")

func _on_log_entry(formatted: String, _cat: String, _level: int) -> void:
	var entry := LogEntry.new(formatted)
	entries.append(entry)
	if entries.size() > MAX_ENTRIES:
		entries.pop_front()
	entry_added.emit(entry)

func _register_default_commands() -> void:

	_commands["help"] = {
		"desc": "Alle verfügbaren Befehle anzeigen",
		"fn": func(_args: Array) -> void:
			var keys := _commands.keys()
			keys.sort()
			var lines: PackedStringArray = []
			for k in keys:
				lines.append("  %-16s %s" % [k, _commands[k].get("desc", "")])
			AppLogger.log_info("Befehle:\n" + "\n".join(lines), "Terminal")
	}

	_commands["clear"] = {
		"desc": "Terminal-Ausgabe leeren",
		"fn": func(_args: Array) -> void:
			entries.clear()
			entry_added.emit(null)
			AppLogger.log_debug("Terminal geleert.", "Terminal")
	}

	_commands["mute"] = {
		"desc": "mute <kategorie> — Kategorie stummschalten",
		"fn": func(args: Array) -> void:
			if args.is_empty():
				AppLogger.log_warn("Verwendung: mute <kategorie>", "Terminal")
				return
			AppLogger.mute_category(args[0])
			AppLogger.log_info("Stummgeschaltet: '%s'" % args[0], "Terminal")
	}

	_commands["unmute"] = {
		"desc": "unmute <kategorie> — Stummschaltung aufheben",
		"fn": func(args: Array) -> void:
			if args.is_empty():
				AppLogger.log_warn("Verwendung: unmute <kategorie>", "Terminal")
				return
			AppLogger.unmute_category(args[0])
			AppLogger.log_info("Reaktiviert: '%s'" % args[0], "Terminal")
	}

	_commands["muted"] = {
		"desc": "Alle stummgeschalteten Kategorien anzeigen",
		"fn": func(_args: Array) -> void:
			var muted := AppLogger.get_muted_categories()
			var msg := "Keine Kategorien stummgeschaltet."
			if not muted.is_empty():
				msg = "Stummgeschaltet: %s" % str(muted)
			AppLogger.log_info(msg, "Terminal")
	}

	_commands["services"] = {
		"desc": "Alle registrierten Services anzeigen",
		"fn": func(_args: Array) -> void:
			var orch := get_node_or_null("/root/ServiceOrchestrator")
			if orch == null:
				AppLogger.log_warn("ServiceOrchestrator nicht verfügbar.", "Terminal")
				return
			var names: Array[String] = orch.get_registered_names()
			names.sort()
			AppLogger.log_info("Services (%d): %s" % [names.size(), str(names)], "Terminal")
	}

	_commands["service"] = {
		"desc": "service <name> — Details zu einem Service",
		"fn": func(args: Array) -> void:
			if args.is_empty():
				AppLogger.log_warn("Verwendung: service <name>", "Terminal")
				return
			var orch := get_node_or_null("/root/ServiceOrchestrator")
			if orch == null:
				AppLogger.log_warn("ServiceOrchestrator nicht verfügbar.", "Terminal")
				return
			var info: Dictionary = orch.get_service_info(args[0])
			AppLogger.log_info("'%s': %s" % [args[0], JSON.stringify(info)], "Terminal")
	}

	_commands["state"] = {
		"desc": "Aktuellen GameState anzeigen",
		"fn": func(_args: Array) -> void:
			var orch := get_node_or_null("/root/ServiceOrchestrator")
			if orch == null:
				AppLogger.log_warn("ServiceOrchestrator nicht verfügbar.", "Terminal")
				return
			var gm: Object = orch.get_service(ServiceKeys.GAME_MANAGER)
			if not is_instance_valid(gm):
				AppLogger.log_warn("GameManager nicht verfügbar.", "Terminal")
				return
			var s = gm.get_state()
			AppLogger.log_info("GameState: %s (%d)" % [GameEnums.State.keys()[s], s], "Terminal")
	}

	_commands["stats"] = {
		"desc": "AppLogger-Statistiken anzeigen",
		"fn": func(_args: Array) -> void:
			AppLogger.log_info(AppLogger.log_summary(), "Terminal")
	}

	_commands["mem"] = {
		"desc": "Speicher-/Objekt-Snapshot jetzt nehmen und anzeigen (siehe TelemetryService)",
		"fn": func(_args: Array) -> void:
			var orch := get_node_or_null("/root/ServiceOrchestrator")
			if orch == null:
				AppLogger.log_warn("ServiceOrchestrator nicht verfügbar.", "Terminal")
				return
			var telemetry: Object = orch.get_service(ServiceKeys.TELEMETRY)
			if not is_instance_valid(telemetry):
				AppLogger.log_warn("TelemetryService nicht verfügbar.", "Terminal")
				return
			# record_memory_snapshot() loggt bereits selbst (INFO, ggf. WARN bei
			# verwaisten Nodes) — hier nur explizit anfordern, kein Doppel-Log.
			telemetry.record_memory_snapshot("terminal_mem")
	}

	_commands["pool"] = {
		"desc": "Entity-Pool-Auslastung anzeigen (Größe/Limit pro Typ + Hits/Misses)",
		"fn": func(_args: Array) -> void:
			var orch := get_node_or_null("/root/ServiceOrchestrator")
			if orch == null:
				AppLogger.log_warn("ServiceOrchestrator nicht verfügbar.", "Terminal")
				return
			var ws: Object = orch.get_service(ServiceKeys.WORLD)
			if not is_instance_valid(ws):
				AppLogger.log_warn("WorldService nicht verfügbar.", "Terminal")
				return
			var info: Dictionary = ws.get_entity_debug_info()
			if info.is_empty():
				AppLogger.log_info("Kein EntityOrchestrator aktiv (Welt nicht geladen?).", "Terminal")
				return
			var sizes: Dictionary = info.get("pool_sizes", {})
			var lines: Array[String] = [
				"Entity-Pool (%d aktive Entities, %d Definitionen):" % [
					info.get("active_entities", 0), (info.get("definitions", []) as Array).size()
				]
			]
			# BUGFIX (2026-09-26, "Telemetrie meldet ständig verwaiste Nodes"): diese Zahlen
			# sind genau die, die früher als "verwaiste Nodes" im Speicher-Snapshot auftauchten
			# (siehe TelemetryService/EntityPool._park_container-Kommentar) — seit dem Fix sind
			# es wieder normale, im EntityPoolContainer geparkte Kindnodes, keine Orphans mehr.
			var non_empty_types: Array = sizes.keys().filter(func(t): return int(sizes[t]["size"]) > 0)
			if non_empty_types.is_empty():
				lines.append("  (alle Pools aktuell leer)")
			else:
				non_empty_types.sort()
				for type_id in non_empty_types:
					var s: Dictionary = sizes[type_id]
					lines.append("  %-20s %2d / %2d" % [type_id, s["size"], s["max"]])
			lines.append("  Hits: %d   Misses: %d" % [info.get("pool_hits", 0), info.get("pool_misses", 0)])
			AppLogger.log_info("\n".join(lines), "Terminal")
	}

	_commands["memhistory"] = {
		"desc": "Alle Speicher-Snapshots dieser Sitzung als Verlauf anzeigen",
		"fn": func(_args: Array) -> void:
			var orch := get_node_or_null("/root/ServiceOrchestrator")
			if orch == null:
				AppLogger.log_warn("ServiceOrchestrator nicht verfügbar.", "Terminal")
				return
			var telemetry: Object = orch.get_service(ServiceKeys.TELEMETRY)
			if not is_instance_valid(telemetry):
				AppLogger.log_warn("TelemetryService nicht verfügbar.", "Terminal")
				return
			var snapshots: Array = telemetry.get_memory_snapshots()
			if snapshots.is_empty():
				AppLogger.log_info("Noch keine Snapshots genommen (auch nicht automatisch — noch keine Session-Grenze erreicht?).", "Terminal")
				return
			var lines: PackedStringArray = ["Speicher-Verlauf (%d Snapshots):" % snapshots.size()]
			for s in snapshots:
				lines.append("  [%6.1fs] %-16s %6.1f MB (Δ%+.2f)  Nodes=%d (Δ%+d)  verwaist=%d (Δ%+d)" % [
					s.get("session_duration_sec", 0.0),
					s.get("label", ""),
					s.get("static_memory_bytes", 0) / 1048576.0,
					(s.get("delta", {}) as Dictionary).get("static_memory_bytes", 0) / 1048576.0,
					s.get("node_count", 0),
					(s.get("delta", {}) as Dictionary).get("node_count", 0),
					s.get("orphan_node_count", 0),
					(s.get("delta", {}) as Dictionary).get("orphan_node_count", 0),
				])
			AppLogger.log_info("\n".join(lines), "Terminal")
	}

	_commands["errors"] = {
		"desc": "Alle ERROR-Logs aus dem Puffer anzeigen",
		"fn": func(_args: Array) -> void:
			var errs := AppLogger.get_errors()
			if errs.is_empty():
				AppLogger.log_info("Keine Fehler im Puffer.", "Terminal")
				return
			AppLogger.log_warn("=== %d Fehler ===" % errs.size(), "Terminal")
			for e in errs:
				AppLogger.log_warn(e.get("formatted", "?"), "Terminal")
	}

	_commands["save"] = {
		"desc": "Spielstand speichern",
		"fn": func(_args: Array) -> void:
			var orch := get_node_or_null("/root/ServiceOrchestrator")
			if orch == null:
				AppLogger.log_warn("ServiceOrchestrator nicht verfügbar.", "Terminal")
				return
			var gs: Object = orch.get_service(ServiceKeys.GAME_SAVE)
			if not is_instance_valid(gs):
				AppLogger.log_warn("GameSaveService nicht verfügbar.", "Terminal")
				return
			var ok = gs.save_all()
			AppLogger.log_info("Gespeichert." if ok else "Speichern fehlgeschlagen!", "Terminal")
	}

	_commands["time"] = {
		"desc": "Weltzeit anzeigen",
		"fn": func(_args: Array) -> void:
			var orch := get_node_or_null("/root/ServiceOrchestrator")
			if orch == null:
				AppLogger.log_warn("ServiceOrchestrator nicht verfügbar.", "Terminal")
				return
			var ws: Object = orch.get_service(ServiceKeys.WORLD)
			if not is_instance_valid(ws):
				AppLogger.log_warn("WorldService nicht verfügbar.", "Terminal")
				return
			AppLogger.log_info(
				"Tag %d — %s" % [ws.day_count, ws.get_formatted_time()],
				"Terminal")
	}

	_commands["status"] = {
		"desc": "Alle registrierten Services und ihren Valid-Status anzeigen",
		"fn": func(_args: Array) -> void:
			var orch := get_node_or_null("/root/ServiceOrchestrator")
			if orch == null:
				AppLogger.log_warn("ServiceOrchestrator nicht verfügbar.", "Terminal")
				return
			var names: Array[String] = orch.get_registered_names()
			var ok: Array = []
			var missing: Array = []
			for name in names:
				var info: Dictionary = orch.get_service_info(name)
				(ok if info.get("valid", false) else missing).append(name)
			AppLogger.log_info("OK (%d): %s" % [ok.size(), str(ok)], "Terminal")
			if not missing.is_empty():
				AppLogger.log_warn("FEHLT (%d): %s" % [missing.size(), str(missing)], "Terminal")
	}

	_commands["loglevel"] = {
		"desc": "loglevel <debug|info|warn|error> — minimalen Level setzen",
		"fn": func(args: Array) -> void:
			if args.is_empty():
				AppLogger.log_warn("Verwendung: loglevel <debug|info|warn|error>", "Terminal")
				return
			match args[0].to_lower():
				"debug": AppLogger.set_min_level(AppLogger.LogLevel.DEBUG)
				"info":  AppLogger.set_min_level(AppLogger.LogLevel.INFO)
				"warn":  AppLogger.set_min_level(AppLogger.LogLevel.WARN)
				"error": AppLogger.set_min_level(AppLogger.LogLevel.ERROR)
				_: AppLogger.log_warn("Unbekannter Level: '%s'" % args[0], "Terminal")
	}

	_commands["exportlog"] = {
		"desc": "Komplettes Log an einen öffentlichen Ort exportieren (Downloads/SAF-Dialog)",
		"fn": func(_args: Array) -> void:
			AppLogger.request_log_export()
	}

	_commands["respawns"] = {
		"desc": "Ausstehende Respawn-Queue anzeigen",
		"fn": func(_args: Array) -> void:
			var orch := get_node_or_null("/root/ServiceOrchestrator")
			if orch == null:
				AppLogger.log_warn("ServiceOrchestrator nicht verfügbar.", "Terminal")
				return
			var rs: Object = orch.get_service(ServiceKeys.RESPAWN)
			if not is_instance_valid(rs):
				AppLogger.log_warn("RespawnService nicht verfügbar.", "Terminal")
				return
			var queue = rs.get_queue_debug()
			if queue.is_empty():
				AppLogger.log_info("Keine ausstehenden Respawns.", "Terminal")
				return
			AppLogger.log_info("Respawn-Queue (%d):" % queue.size(), "Terminal")
			for e in queue:
				AppLogger.log_info(
					"  %s @ %s — in %.0fs" % [e["type"], str(e["pos"]), e["secs"]],
					"Terminal")
	}

	# ADR-025 "Mitigationen" — Tier-2-Geräte-Grenze auf einem echten Host-Handy
	# messen statt schätzen (siehe docs/tier2-device-verification.md für das
	# volle Protokoll). Aggregiert über ALLE authoritativ simulierten Spieler
	# pro Physik-Frame (Player.get_tier2_perf_stats()), nicht pro Spieler.
	_commands["tier2stats"] = {
		"desc": "ADR-025-Perf: authoritative Movement-Simulationskosten pro Physik-Tick (usec)",
		"fn": func(_args: Array) -> void:
			var stats := Player.get_tier2_perf_stats()
			if stats["sample_frames"] == 0:
				AppLogger.log_info(
					"Keine Samples. Läuft nur auf der Autorität (Solo/Host/Server) UND " +
					"nur solange mindestens ein Spieler-Node authoritativ simuliert wird.",
					"Terminal")
				return
			AppLogger.log_info(
				("Tier-2-Perf über %d Physik-Frames: avg=%dusec p95=%dusec max=%dusec " +
				"(Summe über alle gleichzeitig simulierten Spieler pro Frame — " +
				"kein Ersatz für eine echte Messung mit Ziel-Spielerzahl auf " +
				"Referenzgerät, siehe docs/tier2-device-verification.md).") % [
					stats["sample_frames"], stats["avg_usec"], stats["p95_usec"], stats["max_usec"]
				],
				"Terminal")
	}

	_commands["tier2reset"] = {
		"desc": "ADR-025-Perf: Statistik-Ringpuffer zurücksetzen (vor einem sauberen Mess-Lauf)",
		"fn": func(_args: Array) -> void:
			Player.reset_tier2_perf_stats()
			AppLogger.log_info("Tier-2-Perf-Statistik zurückgesetzt.", "Terminal")
	}
