extends Node

## AppLogger — Enterprise-Grade Logging.
##
## AutoLoad #1 — keine Abhängigkeiten, existiert für die gesamte Laufzeit.
##
## Features:
##   - 4 Log-Levels: DEBUG, INFO, WARN, ERROR
##   - Automatischer Stacktrace bei ERROR
##   - Ring-Puffer (500 Einträge) für Terminal-Replay
##   - Hintergrund-Thread für File-I/O — Main-Thread nie blockiert
##   - NDJSON-Dateiformat — direkt ingestierbar von Loki/Datadog/ELK
##   - DEBUG-Sampling in Production (1 in N) — verhindert Log-Flood
##   - Kategorie-basiertes Muting
##   - Performance-Counter: log_count pro Level

signal on_log(formatted: String, category: String, level: int)

enum LogLevel { DEBUG, INFO, WARN, ERROR }

const MAX_BUFFER := 500  # Erhöht für lange Sessions ohne Godot-Editor
const LOG_FILE_NAME := "wildgrove.log"

## Unsichtbares Zero-Width-Space-Präfix vor jedem eigenen print().
## EngineLogBridge (natives Logger-Interface, Godot 4.5+) fängt ALLE prints
## ab, auch unsere eigenen — ohne diese Markierung würde jeder AppLogger-
## Eintrag ein zweites Mal über ingest_engine_event() im Puffer landen.
const OWN_PRINT_MARKER := "\u200b"

## Wird in _ready() gesetzt: zeigt auf den Downloads-Ordner des Systems,
## damit Nutzer die Log-Datei ohne Umwege im Datei-Explorer finden.
## Fällt zurück auf "user://" falls Downloads nicht verfügbar ist
## (z.B. Web-Export oder Plattformen ohne Dateisystem-Zugriff).
var LOG_FILE_PATH: String = "user://" + LOG_FILE_NAME

var enabled_levels: Dictionary = {
	LogLevel.DEBUG: true,
	LogLevel.INFO: true,
	LogLevel.WARN: true,
	LogLevel.ERROR: true,
}

var _muted_categories: Array[String] = []
var _log_buffer: Array[Dictionary] = []
var _file_logging_enabled: bool = false
var _log_file: FileAccess = null

## Main-Thread enqueued Entries — Worker-Thread schreibt sie auf Disk.
var _write_thread:   Thread    = null
var _write_queue:    Array     = []        ## Geschützt durch _queue_mutex
var _queue_mutex:    Mutex     = Mutex.new()
var _thread_running: bool      = false

## Nur 1 in debug_sample_rate DEBUG-Einträge werden emittiert.
## INFO, WARN, ERROR sind immer aktiv.
var debug_sample_rate: int  = 1     ## 1 = alle (Debug-Build), 10 = 1/10 (Production)
var _debug_sample_counter: int = 0

## Kompatibel mit Loki, Datadog, ELK ohne Custom-Parser.
var use_ndjson_format: bool = false  ## Aktiviert via enable_ndjson_logging()

## Performance-Counter — nützlich für Health-Checks
var log_counts: Dictionary = {
	LogLevel.DEBUG: 0,
	LogLevel.INFO: 0,
	LogLevel.WARN: 0,
	LogLevel.ERROR: 0,
}

func _ready() -> void:
	_resolve_log_file_path()

	if not OS.is_debug_build():
		debug_sample_rate = 10
		use_ndjson_format = true

	# File-Logging standardmäßig aktiv im Debug-Build
	if OS.is_debug_build():
		enable_file_logging()

	_thread_running = true
	_write_thread = Thread.new()
	_write_thread.start(_file_writer_loop)

	# Native Logger-Klasse gibt es erst ab Godot 4.5 (GH-91006) — Guard damit
	# das Projekt auf älteren Godot-Versionen nicht beim Parsen bricht.
	if ClassDB.class_exists("Logger"):
		OS.add_logger(EngineLogBridge.new())
		log_debug("EngineLogBridge registriert (native SCRIPT ERROR/push_error-Erfassung aktiv).", "AppLogger")
	else:
		log_debug("Native Logger-Klasse nicht verfügbar (Godot < 4.5) — EngineLogBridge übersprungen.", "AppLogger")

func _notification(what: int) -> void:
	# Round 101 (ADR-045): Crash-Report NUR bei echtem NOTIFICATION_CRASH —
	# bewusst NICHT im gemeinsamen Flush-Block unten, weil WM_CLOSE_REQUEST/
	# PREDELETE normale Beendigungen sind, kein Absturz. Ein Crash-Report bei
	# jedem normalen Fenster-Schließen wäre irreführend.
	if what == NOTIFICATION_CRASH:
		write_crash_report("NOTIFICATION_CRASH")

	# NOTIFICATION_PREDELETE ergänzt: WM_CLOSE_REQUEST feuert nie im headless-Modus
	# (kein Fenster zum Schließen) — z.B. bei `godot --headless -s ... -gexit` in CI.
	# Ohne diesen Fall wird der Worker-Thread nie gestoppt/gejoint, bevor das
	# Autoload-Node (und damit _queue_mutex) zerstört wird → der Thread crasht beim
	# nächsten _queue_mutex.lock() auf einem bereits gefreedeten Mutex.
	# PREDELETE feuert garantiert direkt vor der Zerstörung, egal wie der Prozess endet.
	if (
		what == NOTIFICATION_WM_CLOSE_REQUEST
		or what == NOTIFICATION_CRASH
		or what == NOTIFICATION_PREDELETE
	):
		# Sicherstellen dass alle gepufferten Log-Einträge vor dem Exit
		# geschrieben werden (Crash-Handler Integration).
		_thread_running = false
		if is_instance_valid(_write_thread) and _write_thread.is_started():
			_write_thread.wait_to_finish()
		_close_log_file()

# ─────────────────────────────────────────────
# Öffentliche Log-API
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

## fatal() — für Zustände, in denen das Spiel NICHT sicher weiterlaufen kann
## (z.B. eine Pflicht-Abhängigkeit fehlt komplett zur Boot-Zeit).
##
## Warum nicht einfach assert(false, ...)?
## GDScripts assert() wird in Export-Templates OHNE "Debug"-Häkchen (Shipping/
## Release) komplett rausoptimiert — der Aufruf wird zur No-Op, das Spiel läuft
## mit kaputtem Zustand einfach weiter. fatal() ist ein normaler Funktionsaufruf,
## keine kompilierte Sprach-Konstrukt — bleibt in JEDEM Build-Typ aktiv.
##
## Macht immer, unabhängig vom Build:
##   1. ERROR loggen (inkl. Stacktrace, wie log_error)
##   2. Schreib-Thread synchron flushen — der Grund für den Absturz MUSS auf
##      Disk landen, auch wenn wir im nächsten Frame beenden.
##   3. Spiel kontrolliert beenden (exit code 1) statt mit korruptem State
##      weiterzulaufen und irgendwann woanders unklar zu crashen.
##
## Aufrufer sollten trotzdem direkt danach `return`/`return false` etc. machen —
## quit() wirkt erst zum nächsten Frame, der aktuelle Funktions-Body läuft weiter.
func fatal(msg: String, cat: String = "General") -> void:
	var full_msg := "FATAL: %s" % msg
	_print_log(full_msg, cat, LogLevel.ERROR)
	push_error("[%s] %s" % [cat, full_msg])

	# Round 101 (ADR-045): Crash-Report VOR dem synchronen Flush unten — liest
	# _log_buffer/log_counts (Hauptthread-Felder, siehe write_crash_report()-
	# Kommentar), unabhängig vom Zustand des Schreib-Threads.
	write_crash_report(full_msg)

	# Synchron flushen statt auf den Write-Thread zu vertrauen — wir beenden
	# gleich, die Queue würde sonst nie mehr abgearbeitet.
	_thread_running = false
	if is_instance_valid(_write_thread) and _write_thread.is_started():
		_write_thread.wait_to_finish()
	_close_log_file()

	if is_inside_tree():
		get_tree().quit(1)
	else:
		# Sollte nie passieren (AppLogger ist AutoLoad), aber falls doch:
		# wenigstens den Prozess hart beenden statt still weiterzulaufen.
		OS.crash("AppLogger.fatal() außerhalb des SceneTree aufgerufen: %s" % msg)

## Setzt den minimalen Log-Level (alles darunter wird ignoriert).
## set_min_level(LogLevel.INFO) → kein DEBUG-Spam mehr.
## set_min_level(LogLevel.WARN) → nur Warnungen und Fehler.
func set_min_level(level: LogLevel) -> void:
	enabled_levels[LogLevel.DEBUG] = level <= LogLevel.DEBUG
	enabled_levels[LogLevel.INFO]  = level <= LogLevel.INFO
	enabled_levels[LogLevel.WARN]  = level <= LogLevel.WARN
	enabled_levels[LogLevel.ERROR] = true  # ERROR nie unterdrücken
	log_info("Log-Level gesetzt: %s+" % LogLevel.keys()[level], "AppLogger")

## Druckt eine kompakte Zusammenfassung der Session in den Log.
## Nützlich für den SimpleTerminal 'status'-Befehl.
func log_summary() -> String:
	var errs:  int = log_counts.get(LogLevel.ERROR, 0)
	var warns: int = log_counts.get(LogLevel.WARN,  0)
	var infos: int = log_counts.get(LogLevel.INFO,  0)
	var dbgs:  int = log_counts.get(LogLevel.DEBUG, 0)
	return "Log-Stats: %d ERR | %d WARN | %d INFO | %d DEBUG" % [errs, warns, infos, dbgs]

## Strukturiertes Log mit zusätzlichem Daten-Dictionary.
## Format: [Zeit] [DEBUG] [Kategorie] Nachricht | DATA: {"key": "val"}
func log_trace(msg: String, data: Dictionary = {}, cat: String = "General") -> void:
	_print_log(msg, cat, LogLevel.DEBUG, data)

## Loggt den Start einer wichtigen Operation mit Timer.
## Gibt einen Timestamp zurück — übergib ihn an log_end() für die Elapsed-Zeit.
func log_begin(operation: String, cat: String = "General") -> int:
	var t := Time.get_ticks_msec()
	_print_log("▶ BEGIN: %s" % operation, cat, LogLevel.DEBUG)
	return t

## Loggt das Ende einer Operation mit Elapsed-Zeit.
func log_end(operation: String, started_at: int, cat: String = "General") -> void:
	var elapsed := Time.get_ticks_msec() - started_at
	_print_log("■ END:   %s (%d ms)" % [operation, elapsed], cat, LogLevel.DEBUG)

# ─────────────────────────────────────────────
# File-Logging
# ─────────────────────────────────────────────

## Bestimmt den Standard-Log-Pfad für die laufende Session.
## Android: bleibt bei "user://" — Scoped Storage lässt einen automatischen
## Schreibversuch nach Downloads ohnehin nur still fehlschlagen (kein Crash,
## aber auch keine sichtbare Datei). Für Android gibt es stattdessen
## request_log_export(), das den Log-Text in die Zwischenablage kopiert.
## Alle anderen Plattformen (Desktop): direkt in den echten Downloads-Ordner,
## dort gibt es keine vergleichbare Zugriffsbeschränkung.
func _resolve_log_file_path() -> void:
	if OS.get_name() == "Android":
		LOG_FILE_PATH = "user://" + LOG_FILE_NAME
		return

	var downloads_dir := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)

	if downloads_dir.is_empty():
		push_warning("[AppLogger] Downloads-Ordner nicht verfügbar, nutze user:// als Fallback.")
		LOG_FILE_PATH = "user://" + LOG_FILE_NAME
		return

	var dir_access := DirAccess.open(downloads_dir)
	if dir_access == null:
		push_warning(
			"[AppLogger] Konnte Downloads-Ordner nicht öffnen (%s), nutze user:// als Fallback."
			% downloads_dir
		)
		LOG_FILE_PATH = "user://" + LOG_FILE_NAME
		return

	LOG_FILE_PATH = downloads_dir.path_join(LOG_FILE_NAME)

func enable_file_logging() -> void:
	if _file_logging_enabled:
		return
	_log_file = FileAccess.open(LOG_FILE_PATH, FileAccess.WRITE)
	if _log_file:
		_file_logging_enabled = true
		var header := "=== Session: %s ===" % Time.get_datetime_string_from_system()
		_log_file.store_line(header)
		print(OWN_PRINT_MARKER + "[AppLogger] File-Logging aktiv: %s" % LOG_FILE_PATH)
	else:
		push_warning("[AppLogger] Konnte Log-Datei nicht öffnen: %s" % LOG_FILE_PATH)

func disable_file_logging() -> void:
	_close_log_file()
	_file_logging_enabled = false

# ─────────────────────────────────────────────
# Öffentlicher Log-Export (Android: Zwischenablage / Desktop: direkt)
# ─────────────────────────────────────────────

## Exportiert das komplette aktuelle Log an einen öffentlich zugänglichen Ort.
## Desktop: schreibt sofort in den Downloads-Ordner (kein Dialog nötig).
## Android: Scoped Storage macht "user://" ohne adb unzugänglich. Seit Godot
##          4.6 (GH-112215, volle SAF-Unterstützung) steht dafür der native
##          "Speichern unter"-Systemdialog offen — DisplayServer.file_dialog_
##          show() mit FILE_DIALOG_MODE_SAVE_FILE. Vorher (Projekt war auf
##          4.3 gepinnt) gab es das nicht, daher landete der Log-Text
##          ersatzweise in der System-Zwischenablage. Mit 4.6+ jetzt der
##          echte Dialog; Zwischenablage bleibt als Fallback falls
##          FEATURE_NATIVE_DIALOG_FILE (z.B. sehr alte Android-Systemversion
##          ohne SAF) nicht verfügbar ist.
func request_log_export() -> void:
	if OS.get_name() != "Android":
		var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
		var default_name := "wildgrove_%s.log" % stamp
		var downloads := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
		var path: String
		if downloads.is_empty():
			# Gleicher Degradations-Fall wie in _resolve_log_file_path() (z.B. headless
			# CI, sandboxed Desktop-Umgebung ohne XDG-Downloads) — genauso laut machen,
			# statt den Export still nach user:// umzulenken.
			log_warn(
				"Downloads-Ordner nicht verfügbar — Log-Export landet in user:// (ohne Dateimanager kaum auffindbar).",
				"AppLogger"
			)
			path = "user://" + default_name
		else:
			path = downloads.path_join(default_name)
		_write_log_copy_to(path)
		log_info("Log exportiert nach: %s" % path, "AppLogger")
		return

	if not DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		var text := _read_log_text()
		DisplayServer.clipboard_set(text)
		log_info("Log in Zwischenablage kopiert (%d Zeichen) — nativer Dialog auf diesem Gerät nicht verfügbar." % text.length(), "AppLogger")
		return

	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	var default_name := "wildgrove_%s.log" % stamp
	var err := DisplayServer.file_dialog_show(
		"Log exportieren",
		"",
		default_name,
		false,
		DisplayServer.FILE_DIALOG_MODE_SAVE_FILE,
		PackedStringArray(["*.log ; Log-Dateien"]),
		_on_export_dialog_result
	)
	if err != OK:
		log_warn("SAF-Dialog konnte nicht geöffnet werden (Error %d) — Fallback auf Zwischenablage." % err, "AppLogger")
		var text := _read_log_text()
		DisplayServer.clipboard_set(text)
		log_info("Log in Zwischenablage kopiert (%d Zeichen)." % text.length(), "AppLogger")

## Callback für file_dialog_show() (SAVE_FILE-Modus liefert genau einen Pfad
## in selected_paths, sonst ist der Dialog abgebrochen worden).
func _on_export_dialog_result(status: bool, selected_paths: PackedStringArray, _filter_index: int) -> void:
	if not status or selected_paths.is_empty():
		log_info("Log-Export abgebrochen (kein Pfad gewählt).", "AppLogger")
		return
	_write_log_copy_to(selected_paths[0])
	log_info("Log exportiert nach: %s" % selected_paths[0], "AppLogger")

## Liest den Inhalt der aktuellen user://-Logdatei (falls vorhanden).
## Fällt auf den Ring-Puffer zurück, falls die Datei leer/fehlt.
func _read_log_text() -> String:
	var text := ""
	var src := FileAccess.open("user://" + LOG_FILE_NAME, FileAccess.READ)
	if src:
		text = src.get_as_text()
		src.close()

	if text.is_empty():
		var lines: PackedStringArray = []
		for entry in _log_buffer:
			lines.append(str(entry.get("formatted", "")))
		text = "\n".join(lines)

	return text

## Kopiert den Inhalt der aktuellen user://-Logdatei (falls vorhanden) an
## dest_path. Fällt auf den Ring-Puffer zurück, falls die Datei leer/fehlt.
func _write_log_copy_to(dest_path: String) -> void:
	var text := _read_log_text()

	var dst := FileAccess.open(dest_path, FileAccess.WRITE)
	if not dst:
		log_warn("Konnte Ziel nicht öffnen: %s" % dest_path, "AppLogger")
		return
	dst.store_string(text)
	dst.close()

# ─────────────────────────────────────────────
# Crash-Reporting (Round 101, ADR-045)
# ─────────────────────────────────────────────

## Reine Dictionary-Konstruktion, KEIN Datei-I/O — bewusst getrennt von
## write_crash_report(), damit der Inhalt ohne echtes Dateisystem testbar
## ist (analog wie _to_ndjson() von der eigentlichen Schreib-Logik getrennt
## ist). Liest ausschließlich Hauptthread-Felder (_log_buffer, log_counts) —
## sicher unabhängig vom Zustand des Hintergrund-Schreib-Threads, der nur
## _write_queue anfasst (via _queue_mutex), nie _log_buffer direkt.
func build_crash_report(reason: String) -> Dictionary:
	return {
		"reason": reason,
		"timestamp_unix": Time.get_unix_time_from_system(),
		"timestamp_iso": Time.get_datetime_string_from_system(false, true),
		"godot_version": Engine.get_version_info(),
		"platform": OS.get_name(),
		"log_summary": log_summary(),
		"log_counts": get_log_stats(),
		"recent_errors": get_errors(),
		"recent_log_buffer": peek_log_buffer(),
	}

## Schreibt build_crash_report() als JSON-Datei. Pfad-Auflösung bewusst
## dieselbe Degradations-Kette wie _resolve_log_file_path()/
## request_log_export() (Downloads-Ordner auf Desktop, user:// auf Android
## oder falls Downloads nicht verfügbar) — kein drittes Pfad-Schema im
## Projekt. Best-effort: Schreibfehler werden nur gewarnt, nie propagiert —
## write_crash_report() läuft typischerweise bereits im Begriff, den
## Prozess zu beenden (fatal()/NOTIFICATION_CRASH), ein zweiter Fehler dort
## darf den Shutdown-Pfad nicht selbst zum Absturz bringen.
## Gibt den geschriebenen Pfad zurück, oder "" bei Fehlschlag.
func write_crash_report(reason: String) -> String:
	var report := build_crash_report(reason)
	var path := _crash_report_path()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if not f:
		push_warning("[AppLogger] Konnte Crash-Report nicht schreiben: %s" % path)
		return ""
	f.store_string(JSON.stringify(report, "\t"))
	f.close()
	return path

func _crash_report_path() -> String:
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	var filename := "wildgrove_crash_%s.json" % stamp
	if OS.get_name() == "Android":
		return "user://" + filename
	var downloads_dir := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	if downloads_dir.is_empty():
		return "user://" + filename
	return downloads_dir.path_join(filename)

# ─────────────────────────────────────────────
# Kategorie-Kontrolle
# ─────────────────────────────────────────────

func mute_category(cat: String) -> void:
	var lower := cat.to_lower()
	if lower not in _muted_categories:
		_muted_categories.append(lower)
		print(OWN_PRINT_MARKER + "[AppLogger] Kategorie stummgeschaltet: '%s'" % cat)

func unmute_category(cat: String) -> void:
	_muted_categories.erase(cat.to_lower())

func get_muted_categories() -> Array[String]:
	return _muted_categories.duplicate()

# ─────────────────────────────────────────────
# Puffer-Zugriff
# ─────────────────────────────────────────────

## Gibt den Puffer zurück UND leert ihn. Für SimpleTerminal-Replay.
func flush_log_buffer() -> Array[Dictionary]:
	var copy := _log_buffer.duplicate()
	_log_buffer.clear()
	return copy

## Gibt den Puffer zurück OHNE ihn zu leeren. Für Debug-Inspektion.
func peek_log_buffer() -> Array[Dictionary]:
	return _log_buffer.duplicate()

## Gibt die Anzahl der Logs pro Level zurück.
func get_log_stats() -> Dictionary:
	return log_counts.duplicate()

## Gibt alle ERROR-Logs aus dem Puffer zurück.
func get_errors() -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	for entry in _log_buffer:
		if entry.get("level") == LogLevel.ERROR:
			errors.append(entry)
	return errors

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _print_log(msg: String, cat: String, level: int, data: Dictionary = {}) -> void:
	if not enabled_levels.get(level, true):
		return
	if cat.to_lower() in _muted_categories:
		return

	var time: String = Time.get_datetime_string_from_system(false, true)
	var level_keys: Array = LogLevel.keys()
	var lvl_str: String = (
		level_keys[level] if level >= 0 and level < level_keys.size() else "UNKNOWN"
	)

	# Automatischer Stacktrace bei ERROR
	var final_msg := msg
	if level == LogLevel.ERROR:
		var stack := _format_stacktrace(get_stack())
		if not stack.is_empty():
			final_msg += "\n" + stack

	var data_str: String = ""
	if not data.is_empty():
		data_str = " | DATA: " + JSON.stringify(data)

	var formatted: String = "[%s] [%s] [%s] %s%s" % [time, lvl_str, cat, final_msg, data_str]

	_record(formatted, cat, level, msg, data, true)

## Gemeinsamer Kern für _print_log() (eigene Logs) und ingest_engine_event()
## (Engine-Logs via EngineLogBridge). do_print steuert ob print() aufgerufen
## wird — bei Engine-Events NIE true, siehe ingest_engine_event().
func _record(
	formatted: String, cat: String, level: int, msg: String, data: Dictionary, do_print: bool
) -> void:
	# Ring-Puffer
	var entry := {"formatted": formatted, "category": cat, "level": level, "msg": msg, "data": data}
	_log_buffer.append(entry)
	if _log_buffer.size() > MAX_BUFFER:
		_log_buffer.pop_front()

	# Counter
	if log_counts.has(level):
		log_counts[level] += 1

	if do_print:
		# OWN_PRINT_MARKER davor — sonst fängt EngineLogBridge._log_message()
		# unseren eigenen print() ab und speist ihn ein zweites Mal ein.
		print(OWN_PRINT_MARKER + formatted)

	if level == LogLevel.DEBUG and debug_sample_rate > 1:
		_debug_sample_counter += 1
		if _debug_sample_counter % debug_sample_rate != 0:
			on_log.emit(formatted, cat, level)
			return

	if _file_logging_enabled:
		_queue_mutex.lock()
		_write_queue.append({"formatted": formatted, "entry": entry, "ndjson": use_ndjson_format})
		_queue_mutex.unlock()

	on_log.emit(formatted, cat, level)

## Wird ausschließlich von EngineLogBridge aufgerufen (natives Logger-
## Interface, Godot 4.5+), um SCRIPT ERROR / push_error() / push_warning() /
## print() der Engine in denselben Puffer und dieselbe Datei einzuspeisen
## wie unsere eigenen log_*()-Aufrufe.
##
## WICHTIG: Ruft niemals push_error()/push_warning()/log_error() oder print()
## auf — jedes davon würde den nativen Logger erneut triggern (OS.add_logger-
## Callback) und in einer Rekursion enden. Nur _record() mit do_print=false —
## die Engine hat die Nachricht bereits selbst ausgegeben, ein zweiter
## print()-Aufruf würde sie nur doppelt anzeigen.
func ingest_engine_event(msg: String, cat: String, level: int) -> void:
	if not enabled_levels.get(level, true):
		return
	if cat.to_lower() in _muted_categories:
		return
	var time: String = Time.get_datetime_string_from_system(false, true)
	var level_keys: Array = LogLevel.keys()
	var lvl_str: String = (
		level_keys[level] if level >= 0 and level < level_keys.size() else "UNKNOWN"
	)
	var formatted: String = "[%s] [%s] [%s] %s" % [time, lvl_str, cat, msg]
	_record(formatted, cat, level, msg, {}, false)

func _format_stacktrace(stack: Array) -> String:
	if stack.is_empty():
		return ""
	var lines: PackedStringArray = PackedStringArray(["Stacktrace:"])
	for frame in stack:
		var source: String = str(frame.get("source", ""))
		var function: String = str(frame.get("function", "?"))
		var line: int = int(frame.get("line", 0))
		# AppLogger-interne Frames überspringen
		if source.ends_with("AppLogger.gd") or function in ["_print_log", "log_error"]:
			continue
		lines.append("  %s:%d in %s()" % [source, line, function])
	return "\n".join(lines)

func _close_log_file() -> void:
	if is_instance_valid(_log_file):
		_log_file.flush()
		_log_file.close()
		_log_file = null

# ─────────────────────────────────────────────
# ─────────────────────────────────────────────

## Worker-Schleife — läuft auf dem Background-Thread.
## Schreibt log entries aus _write_queue auf Disk ohne Main-Thread zu blockieren.
func _file_writer_loop() -> void:
	while _thread_running or not _write_queue.is_empty():
		# Batch verarbeiten — alle aktuell in der Queue stehenden Einträge
		_queue_mutex.lock()
		var batch: Array = _write_queue.duplicate()
		_write_queue.clear()
		_queue_mutex.unlock()

		if not batch.is_empty() and _file_logging_enabled and is_instance_valid(_log_file):
			for item in batch:
				if item.get("ndjson", false):
					_log_file.store_line(_to_ndjson(item["entry"]))
				else:
					_log_file.store_line(item["formatted"])
			_log_file.flush()  # Expliziter Flush pro Batch

		# 16ms Sleep — vermeidet Busy-Wait, bleibt reaktiv genug
		if _thread_running:
			OS.delay_msec(16)

	print(OWN_PRINT_MARKER + "[AppLogger] File-Writer-Thread beendet.")

## Konvertiert einen Log-Entry in NDJSON-Format.
## Ein JSON-Objekt pro Zeile — direkt ingestierbar von Loki/Datadog/ELK.
func _to_ndjson(entry: Dictionary) -> String:
	var level_keys: Array = LogLevel.keys()
	var level_int: int    = entry.get("level", 0)
	var level_str: String = level_keys[level_int] if level_int < level_keys.size() else "UNKNOWN"

	var ndjson_obj := {
		"ts":      Time.get_unix_time_from_system(),
		"level":   level_str,
		"cat":     entry.get("category", ""),
		"msg":     entry.get("msg", ""),
	}
	if not entry.get("data", {}).is_empty():
		ndjson_obj["data"] = entry["data"]
	return JSON.stringify(ndjson_obj)

## Aktiviert NDJSON-Format für externe Log-Aggregatoren (Loki, Datadog, ELK).
## Überschreibt das bestehende Log-File mit NDJSON-Header-Kommentar.
func enable_ndjson_logging() -> void:
	use_ndjson_format = true
	print(OWN_PRINT_MARKER + "[AppLogger] NDJSON-Format aktiviert.")
