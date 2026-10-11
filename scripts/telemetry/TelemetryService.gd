extends Service
class_name TelemetryService

## ADR-045: Telemetrie/Crash-Reporting — Telemetrie-Hälfte.
##
## record_event() ist bewusst NUR ein dünner Wrapper um AppLogger.log_trace()
## mit der Kategorie "Telemetry" — KEINE eigene Datei-I/O, KEIN eigener
## Ring-Puffer, KEIN eigener Thread. AppLogger hat das alles bereits
## (NDJSON-Format, Hintergrund-Schreib-Thread, Ring-Puffer, Kategorie-
## basiertes Stummschalten via AppLogger.mute_category("Telemetry")) — ein
## zweites File-I/O-System nur für Telemetrie-Events wäre reine Dopplung.
## Dieser Service liefert nur, was AppLogger NICHT hat: pro-Event-Namen
## aggregierte Zähler für die laufende Sitzung (get_event_counts()) — für
## eine künftige Debug-/Status-Anzeige, ohne den kompletten Log-Ringpuffer
## durchsuchen zu müssen.
##
## KEIN Netzwerk-Upload — es gibt (noch) keinen Telemetrie-Server/-Endpunkt
## im Projekt. Events landen ausschließlich lokal in der bestehenden
## Log-Datei (NDJSON, Kategorie "Telemetry") — filterbar/ingestierbar mit
## denselben Werkzeugen wie der Rest des Logs (Loki/Datadog/ELK, siehe
## AppLogger-Klassenkommentar), sobald ein Upload-Pfad gebraucht wird.
##
## KEINE Persistenz der Zähler — Session-only, setzt bei jedem Neustart
## zurück, analog Chat (ADR-043). Die zugrundeliegenden Rohdaten (die
## einzelnen log_trace()-Aufrufe) überleben dagegen sehr wohl in der
## Log-Datei — nur die AGGREGATION hier ist transient.
##
## Zwei automatische Beispiel-Events (session_start/session_end) sind
## bewusst mit eingebaut, statt den Service komplett ungenutzt zu lassen —
## sonst gäbe es 0 tatsächliche Aufrufer dieser neuen Infrastruktur, exakt
## das Muster, das in früheren Runden (z.B. ADR-042) bewusst vermieden
## wurde, wo es machbar war.
##
## BEWUSST NICHT TEIL DIESER RUNDE: kein Netzwerk-Upload/Endpunkt (siehe
## oben), keine Opt-out-/Datenschutz-Einstellung (bislang rein lokal, kein
## Datenabfluss — sobald ein Upload-Pfad existiert, wird das relevant und
## muss dann nachgezogen werden), kein `UIContext`-Eintrag (die einzige
## bisherige UI-Anbindung läuft über AdminPanelUI direkt gegen den Service,
## nicht über UIContext — siehe dortige Diagnose-Sektion).
##
## ERWEITERUNG (2026-09-25): Speicher-/Objekt-Snapshots.
##
## Anlass: die Session heute hat mehrere "Zombie"-Bugs gefunden (BUG-1,
## BUG-2, BUG-B) — Services/Controller, die bei Szenen-/Charakterwechsel
## nicht sauber abgebaut wurden und sich unsichtbar akkumuliert haben, bis
## sie sich durch DOPPELTE Effekte bemerkbar gemacht haben (doppelte UI,
## doppelte Interaktionen). Nicht jeder Leak verdoppelt sichtbar etwas —
## die meisten wachsen einfach nur RAM-Verbrauch/Objekt-/Node-Zahl über die
## Zeit, ohne ein offensichtliches Symptom, bis das Spiel nach Stunden
## langsam wird oder abstürzt. record_memory_snapshot() macht genau DAS
## sichtbar: Godots eingebaute Performance-Monitore (kein neuer Zähl-
## Mechanismus, keine eigene Instrumentierung nötig) + statischer
## Speicherverbrauch, geloggt mit Delta zum letzten Snapshot — Wachstum
## fällt damit sofort im Log auf, auch ohne dass man weiß, wonach man sucht.
##
## Automatisch mitgeschnitten an den beiden Stellen, an denen genau diese
## Zombie-Bugs sichtbar würden: EventBus.session.session_ready (nach Boot)
## und session_unloaded (nach Teardown) — Speicher/Objekt-/Node-Zahl sollte
## über mehrere Charakterwechsel hinweg zur selben Baseline zurückkehren;
## tut sie das nicht, wächst irgendwo etwas unbegrenzt. Zusätzlich alle
## MEMORY_SAMPLE_INTERVAL_SEC ein periodischer Snapshot über den
## ServiceTicker (siehe on_tick()), um auch Leaks WÄHREND einer laufenden
## Session zu fangen, nicht nur an Szenengrenzen.
##
## Bewusst weiterhin nur AppLogger.log_trace() (Kategorie "Telemetry") als
## Senke — kein zusätzlicher Persistenz-/Upload-Pfad, siehe Klassenkommentar
## oben. get_memory_snapshots() hält zusätzlich die letzten
## MAX_MEMORY_HISTORY Snapshots im Speicher (Session-only) für eine
## künftige Debug-Anzeige (SimpleTerminal-Befehl `mem`, siehe dort).
##
## ERWEITERUNG (2026-10-11, Issue #1 — Performance/Lag): FPS- und
## Frame-Time-Metriken + Tick-Statistiken des ServiceTicker in jedem
## Snapshot. Vorher zeigte ein Snapshot nur Speicher/Objekt-Zahlen — man
## sah, DASS das Spiel laggt, aber nicht WER die Frame-Zeit verbraucht.
## Jetzt: fps/process_time_ms pro Snapshot plus avg/letzte on_tick()-Dauer
## pro Service (siehe ServiceTicker.get_tick_stats()) — das nächste Log
## benennt den Verursacher direkt.

const LOG_CAT := "Telemetry"

## Wie oft on_tick() einen automatischen Speicher-Snapshot nimmt.
const MEMORY_SAMPLE_INTERVAL_SEC := 60.0

## Wie viele Snapshots get_memory_snapshots() im Speicher vorhält (Ring-Puffer,
## älteste zuerst verworfen) — begrenzt, damit DIESE Diagnose-Hilfe nicht
## selbst zu einem (kleinen, aber unnötigen) Leak wird.
const MAX_MEMORY_HISTORY := 200

## Ab dieser durchschnittlichen on_tick()-Dauer (Mikrosekunden) bekommt ein
## Service einen DEBUG-Eintrag im Snapshot-Log (Issue #1) — macht heiße
## Kandidaten ohne Nachrechnen im Trace sichtbar.
const TICK_SLOW_THRESHOLD_US := 500.0

## Event-Namen -> Anzahl in dieser Sitzung. Rein transient (siehe
## Klassenkommentar).
var _event_counts: Dictionary = {}

var _session_start_unix: float = 0.0

## Ring-Puffer der letzten Speicher-Snapshots (siehe MAX_MEMORY_HISTORY).
## Jeder Eintrag: das Dictionary, das record_memory_snapshot() zurückgibt.
var _memory_snapshots: Array[Dictionary] = []

## Letzter Snapshot — Basis für die Delta-Berechnung im nächsten Aufruf.
var _last_memory_snapshot: Dictionary = {}

var _ticker: ServiceTicker = null
var _time_since_last_sample_sec: float = 0.0

func configure(deps: ServiceDeps) -> void:
	_session_start_unix = Time.get_unix_time_from_system()
	_ticker = deps.get_optional(ServiceKeys.TICKER) as ServiceTicker
	AppLogger.log_info("TelemetryService initialisiert.", LOG_CAT)
	record_event("session_start")

func on_ready() -> void:
	if is_instance_valid(_ticker):
		_ticker.register_service(self)
	else:
		AppLogger.log_warn(
			"Kein ServiceTicker verfügbar — periodisches Speicher-Sampling deaktiviert (Snapshots an Session-Grenzen laufen trotzdem).",
			LOG_CAT
		)
	# Zombie-Service-Erkennung (siehe Klassenkommentar "Erweiterung"): Snapshot
	# direkt nach jedem erfolgreichen Boot UND direkt nach jedem Teardown.
	# Über mehrere Charakterwechsel hinweg sollte "nach Teardown" immer wieder
	# ungefähr dieselbe Baseline zeigen — wächst sie stattdessen stetig, bleibt
	# irgendwo etwas am Leben, das nicht mehr sollte.
	EventBus.session.session_ready.connect(func() -> void: record_memory_snapshot("session_ready"))
	EventBus.session.session_unloaded.connect(func() -> void: record_memory_snapshot("session_unloaded"))

func on_cleanup() -> void:
	record_event("session_end", {"duration_sec": get_session_duration_sec()})
	_event_counts.clear()
	_memory_snapshots.clear()
	_last_memory_snapshot.clear()

## Performance-Fix (Issue #1): Telemetrie-Sampling braucht kein 60-Hz-Polling.
## on_tick() akkumuliert delta und feuert erst ab MEMORY_SAMPLE_INTERVAL_SEC —
## 1 Hz genügt völlig. Siehe ServiceTicker (intervall-basiertes Throttling);
## on_tick() bekommt die aufsummierte Delta-Zeit des Intervalls übergeben.
func get_tick_interval() -> float:
	return 1.0

## Periodisches Sampling — registriert über ServiceTicker (siehe on_ready()).
## Läuft nur, wenn ein Ticker verfügbar ist (siehe configure()).
func on_tick(delta: float) -> void:
	_time_since_last_sample_sec += delta
	if _time_since_last_sample_sec < MEMORY_SAMPLE_INTERVAL_SEC:
		return
	_time_since_last_sample_sec = 0.0
	record_memory_snapshot("periodic")

## Zeichnet ein einzelnes Ereignis auf. `properties` ist ein freies
## Dictionary (muss JSON-serialisierbar sein — AppLogger.log_trace()
## stringifiziert es für die Log-Zeile, siehe dortiger Kommentar zu
## `data_str`). Leere event_name wird stillschweigend ignoriert (kein
## Fehler-Signal nötig — Telemetrie ist nicht kritischer Pfad, ein
## verpasstes Event darf kein Fehlerzustand für den Aufrufer sein).
func record_event(event_name: String, properties: Dictionary = {}) -> void:
	var clean_name := event_name.strip_edges()
	if clean_name.is_empty():
		return
	_event_counts[clean_name] = int(_event_counts.get(clean_name, 0)) + 1
	AppLogger.log_trace(clean_name, properties, LOG_CAT)

## Aggregierte Zähler für die laufende Sitzung. Kopie — Aufrufer dürfen die
## interne Struktur nicht mutieren.
func get_event_counts() -> Dictionary:
	return _event_counts.duplicate()

func get_event_count(event_name: String) -> int:
	return int(_event_counts.get(event_name, 0))

func get_session_duration_sec() -> float:
	return Time.get_unix_time_from_system() - _session_start_unix

# ─────────────────────────────────────────────
# Speicher-/Objekt-Snapshots (siehe Klassenkommentar "Erweiterung")
# ─────────────────────────────────────────────

## Nimmt einen Snapshot von Godots eingebauten Performance-Monitoren +
## statischem Speicherverbrauch, loggt ihn (mit Delta zum vorherigen
## Snapshot) als Telemetrie-Event und gibt ihn zurück.
##
## [param label] Freier Text zur Einordnung im Log (z.B. "session_ready",
##               "periodic", oder ein von außen übergebener Ort wie
##               "vor_charakterwechsel"). Leer erlaubt.
##
## Nutzt bewusst nur langjährig stabile, seit Godot 3 unveränderte APIs
## (Performance.MEMORY_STATIC/OBJECT_COUNT/OBJECT_NODE_COUNT/
## OBJECT_ORPHAN_NODE_COUNT/OBJECT_RESOURCE_COUNT, OS.get_static_memory_usage()/
## get_static_memory_peak_usage()) — keine GPU-/Render-Monitore, die je nach
## Godot-Minor-Version umbenannt wurden.
## FPS/Frame-Time (TIME_FPS/TIME_PROCESS) sind同样 stabil und seit Issue #1
## Teil jedes Snapshots.
##
## OBJECT_ORPHAN_NODE_COUNT ist der mit Abstand wichtigste Einzelwert für
## GENAU die Bug-Klasse von heute: ein Node, der aus dem Baum entfernt aber
## nie freigegeben wurde (z.B. ein UI-Controller/eine Weapon-Visual-Instanz
## bei fehlendem Teardown), taucht hier als "verwaister Node" auf, lange
## bevor er sich anderweitig bemerkbar macht.
func record_memory_snapshot(label: String = "") -> Dictionary:
	var snapshot := {
		"label": label,
		"unix_time": Time.get_unix_time_from_system(),
		"session_duration_sec": get_session_duration_sec(),
		"static_memory_bytes": OS.get_static_memory_usage(),
		"static_memory_peak_bytes": OS.get_static_memory_peak_usage(),
		"object_count": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"node_count": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphan_node_count": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"resource_count": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"fps": int(Performance.get_monitor(Performance.TIME_FPS)),
		"process_time_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
	}

	# Issue #1: Tick-Statistiken des ServiceTicker mit in den Snapshot —
	# avg./letzte on_tick()-Dauer pro Service macht den Frame-Zeit-Verbraucher
	# im nächsten Log direkt namentlich sichtbar.
	if is_instance_valid(_ticker):
		snapshot["tick_stats"] = _ticker.get_tick_stats()

	var delta: Dictionary = {}
	if not _last_memory_snapshot.is_empty():
		for key in ["static_memory_bytes", "object_count", "node_count", "orphan_node_count", "resource_count"]:
			delta[key] = int(snapshot[key]) - int(_last_memory_snapshot.get(key, 0))
	snapshot["delta"] = delta

	_last_memory_snapshot = snapshot
	_memory_snapshots.append(snapshot)
	if _memory_snapshots.size() > MAX_MEMORY_HISTORY:
		_memory_snapshots.pop_front()

	record_event("memory_snapshot", snapshot)

	# Zusätzlich auf INFO-Level (nicht nur TRACE über record_event) — Wachstum
	# soll auch beim normalen Mitlesen im Terminal auffallen, nicht nur beim
	# gezielten Durchsuchen der Log-Datei nach "Telemetry".
	AppLogger.log_info(
		"Speicher-Snapshot%s: %.1f MB statisch (Δ%+.2f MB), %d Objekte (Δ%+d), %d Nodes (Δ%+d), %d verwaiste Nodes (Δ%+d), %d Resourcen (Δ%+d) | FPS: %d, Frame: %.2f ms." % [
			(" [%s]" % label) if not label.is_empty() else "",
			snapshot["static_memory_bytes"] / 1048576.0,
			delta.get("static_memory_bytes", 0) / 1048576.0,
			snapshot["object_count"], delta.get("object_count", 0),
			snapshot["node_count"], delta.get("node_count", 0),
			snapshot["orphan_node_count"], delta.get("orphan_node_count", 0),
			snapshot["resource_count"], delta.get("resource_count", 0),
			snapshot["fps"],
			snapshot["process_time_ms"],
		],
		LOG_CAT
	)

	# Issue #1: Services mit auffällig teuren on_tick()-Aufrufen direkt im
	# Snapshot-Log benennen (DEBUG-Level) — kein Nachrechnen im Trace nötig.
	if snapshot.has("tick_stats"):
		for entry in snapshot["tick_stats"]:
			var calls := int(entry.get("calls", 0))
			if calls <= 0:
				continue
			var avg_us := float(entry.get("total_us", 0)) / float(calls)
			if avg_us >= TICK_SLOW_THRESHOLD_US:
				AppLogger.log_debug(
					"Tick-Statistik: '%s' Ø %.0f µs/Tick (%d Aufrufe, Intervall: %s s)."
					% [entry.get("class", "?"), avg_us, calls, str(entry.get("interval", 0.0))],
					LOG_CAT
				)

	if int(snapshot["orphan_node_count"]) > 0:
		AppLogger.log_warn(
			"%d verwaiste Node(s) erkannt — möglicher Teardown-Bug (siehe TelemetryService-Klassenkommentar zu BUG-1/BUG-2/BUG-B)." % snapshot["orphan_node_count"],
			LOG_CAT
		)

	return snapshot

## Alle bisher genommenen Snapshots dieser Sitzung, älteste zuerst (Kopie).
func get_memory_snapshots() -> Array[Dictionary]:
	return _memory_snapshots.duplicate(true)

## Der zuletzt genommene Snapshot, oder ein leeres Dictionary wenn noch keiner
## existiert.
func get_last_memory_snapshot() -> Dictionary:
	return _last_memory_snapshot.duplicate(true)

# ─────────────────────────────────────────────
# Copy/Export (BUGFIX/ERWEITERUNG 2026-09-27, "Copy/Export-Button wie bei Logs, nur für
# Telemetrie") — spiegelt SimpleTerminal.get_all_text()/export_all_text_to_file() 1:1:
# gleiches Format (Klartext, ein Eintrag pro Zeile), gleicher Ablageort (user://), gleiche
# Grund für die zusätzliche Datei (siehe dortiger Kommentar zu Clipboard-Kürzung auf Mobile).
# ─────────────────────────────────────────────

## Formatiert Event-Zähler + alle Speicher-Snapshots dieser Sitzung als lesbaren Klartext —
## für den "COPY ALL"-Button im Admin-Panel (Diagnose-Sektion) und export_all_text_to_file().
func get_all_text() -> String:
	var lines := PackedStringArray()
	lines.append("=== Telemetrie-Export (Session-Dauer: %.0f s) ===" % get_session_duration_sec())
	lines.append("")
	lines.append("-- Event-Zähler --")
	if _event_counts.is_empty():
		lines.append("(keine Events aufgezeichnet)")
	else:
		var names := _event_counts.keys()
		names.sort()
		for event_name in names:
			lines.append("  %-24s %d" % [event_name, _event_counts[event_name]])
	lines.append("")
	lines.append("-- Speicher-Snapshots (%d, älteste zuerst) --" % _memory_snapshots.size())
	if _memory_snapshots.is_empty():
		lines.append("(noch kein Snapshot genommen)")
	else:
		for snapshot in _memory_snapshots:
			var delta: Dictionary = snapshot.get("delta", {})
			lines.append(
				"  [%s] %d FPS, %.2f ms Frame | %.1f MB (Δ%+.2f MB), %d Objekte (Δ%+d), %d Nodes (Δ%+d), %d verwaiste Nodes (Δ%+d), %d Resourcen (Δ%+d)" % [
					snapshot.get("label", ""),
					int(snapshot.get("fps", 0)),
					float(snapshot.get("process_time_ms", 0.0)),
					int(snapshot.get("static_memory_bytes", 0)) / 1048576.0,
					int(delta.get("static_memory_bytes", 0)) / 1048576.0,
					int(snapshot.get("object_count", 0)), int(delta.get("object_count", 0)),
					int(snapshot.get("node_count", 0)), int(delta.get("node_count", 0)),
					int(snapshot.get("orphan_node_count", 0)), int(delta.get("orphan_node_count", 0)),
					int(snapshot.get("resource_count", 0)), int(delta.get("resource_count", 0)),
				]
			)
	return "
".join(lines)

## Schreibt get_all_text() als eigene Datei nach user:// — siehe SimpleTerminal.
## export_all_text_to_file()-Kommentar: umgeht OS-seitige Clipboard-Größenlimits (v.a. auf
## Mobile), die DisplayServer.clipboard_set() lange Texte klammheimlich kürzen lassen können.
func export_all_text_to_file() -> String:
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	var path := "user://telemetry_export_%s.log" % stamp
	var f := FileAccess.open(path, FileAccess.WRITE)
	if not f:
		AppLogger.log_warn("Konnte Telemetrie-Export-Datei nicht öffnen: %s" % path, LOG_CAT)
		return ""
	f.store_string(get_all_text())
	f.close()
	return path
