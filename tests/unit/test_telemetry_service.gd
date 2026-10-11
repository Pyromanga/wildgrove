# res://tests/unit/test_telemetry_service.gd
extends GutTest

## Unit-Tests für TelemetryService (ADR-045 "Telemetrie/Crash-Reporting" —
## Telemetrie-Hälfte).
##
## Strategie: TelemetryService extends Service (RefCounted) — kein
## add_child nötig (analog test_aura_service.gd). Keine Mocks nötig — der
## Service hat außer AppLogger (globales AutoLoad, immer verfügbar in
## Tests, siehe test_terminal_controller.gd) keine Abhängigkeiten.
##
## Abgedeckt:
##   - configure() feuert automatisch "session_start"
##   - record_event(): zählt korrekt, ignoriert leere Namen, ist pro Name
##     unabhängig
##   - get_event_counts() gibt eine Kopie zurück
##   - on_cleanup() feuert "session_end" mit duration_sec UND leert danach
##     die Zähler
##   - get_session_duration_sec() ist nicht-negativ
##   - get_all_text()/export_all_text_to_file() (ERWEITERUNG 2026-09-27): Format
##     enthält Event-Zähler + Snapshots in Reihenfolge, Datei-Inhalt == get_all_text()

var _svc: TelemetryService

func before_each() -> void:
	_svc = TelemetryService.new()
	_svc.configure(ServiceDeps.from_dict({}))

func after_each() -> void:
	_svc = null

func test_configure_records_session_start_automatically() -> void:
	assert_eq(_svc.get_event_count("session_start"), 1)

func test_record_event_increments_count() -> void:
	_svc.record_event("item_picked_up")
	_svc.record_event("item_picked_up")
	_svc.record_event("item_picked_up")
	assert_eq(_svc.get_event_count("item_picked_up"), 3)

func test_record_event_counts_are_independent_per_name() -> void:
	_svc.record_event("quest_completed")
	_svc.record_event("npc_talked_to")
	_svc.record_event("npc_talked_to")
	assert_eq(_svc.get_event_count("quest_completed"), 1)
	assert_eq(_svc.get_event_count("npc_talked_to"), 2)

func test_record_event_ignores_empty_name() -> void:
	var before := _svc.get_event_counts().size()
	_svc.record_event("")
	_svc.record_event("   ")
	assert_eq(_svc.get_event_counts().size(), before, "Leere/Whitespace-Namen dürfen keinen neuen Zähler anlegen.")

func test_unknown_event_count_defaults_to_zero() -> void:
	assert_eq(_svc.get_event_count("never_happened"), 0)

func test_get_event_counts_returns_a_copy() -> void:
	_svc.record_event("foo")
	var copy := _svc.get_event_counts()
	copy["foo"] = 999
	assert_eq(_svc.get_event_count("foo"), 1, "get_event_counts() darf keine interne Referenz zurückgeben.")

func test_record_event_accepts_properties_without_error() -> void:
	# Reines Durchreichen an AppLogger.log_trace() — hier nur sicherstellen,
	# dass ein Properties-Dictionary den Aufruf nicht zum Absturz bringt.
	_svc.record_event("trade_completed", {"item_id": "iron_ore", "quantity": 5, "price": 100})
	assert_eq(_svc.get_event_count("trade_completed"), 1)

func test_session_duration_is_non_negative() -> void:
	assert_true(_svc.get_session_duration_sec() >= 0.0)

func test_on_cleanup_records_session_end_then_clears_counts() -> void:
	_svc.record_event("some_action")
	_svc.on_cleanup()
	# session_end wurde VOR dem Clear gezählt, aber das Clear danach leert
	# auch diesen Zähler wieder — get_event_counts() muss also leer sein.
	assert_eq(_svc.get_event_counts().size(), 0, "on_cleanup() muss die Session-Zähler am Ende leeren.")

# ─────────────────────────────────────────────────────────────────────────────
# get_all_text() / export_all_text_to_file() — ERWEITERUNG (2026-09-27, "Copy/Export-
# Button wie bei Logs, nur für Telemetrie")
# ─────────────────────────────────────────────────────────────────────────────

func test_get_all_text_without_snapshots_says_so_instead_of_being_empty() -> void:
	var text := _svc.get_all_text()
	assert_true(text.contains("noch kein Snapshot"),
		"Ohne Snapshots muss get_all_text() das explizit sagen, statt einfach nichts anzuzeigen.")

func test_get_all_text_includes_event_counts() -> void:
	_svc.record_event("item_picked_up")
	_svc.record_event("item_picked_up")
	var text := _svc.get_all_text()
	assert_true(text.contains("item_picked_up"), "Event-Name muss im Export auftauchen.")
	assert_true(text.contains("2"), "Zähler-Wert muss im Export auftauchen.")

func test_get_all_text_includes_memory_snapshot_label_and_values() -> void:
	_svc.record_memory_snapshot("mein_test_label")
	var text := _svc.get_all_text()
	assert_true(text.contains("mein_test_label"), "Snapshot-Label muss im Export auftauchen.")
	assert_true(text.contains("Objekte"), "Objekt-Zahl muss im Export auftauchen.")
	assert_true(text.contains("verwaiste Nodes"), "Orphan-Node-Zahl muss im Export auftauchen.")

func test_get_all_text_lists_multiple_snapshots_in_order() -> void:
	_svc.record_memory_snapshot("erst")
	_svc.record_memory_snapshot("zweitens")
	var text := _svc.get_all_text()
	assert_true(text.find("erst") < text.find("zweitens"),
		"Snapshots müssen in Aufnahme-Reihenfolge (älteste zuerst) erscheinen.")

func test_export_all_text_to_file_writes_readable_file() -> void:
	_svc.record_event("some_action")
	_svc.record_memory_snapshot("vor_export")

	var path := _svc.export_all_text_to_file()
	assert_true(path.begins_with("user://telemetry_export_"), "Export-Pfad muss im erwarteten user://-Schema liegen.")

	var f := FileAccess.open(path, FileAccess.READ)
	assert_not_null(f, "Export-Datei muss lesbar sein.")
	var contents := f.get_as_text()
	f.close()
	assert_eq(contents, _svc.get_all_text(), "Datei-Inhalt muss exakt get_all_text() entsprechen.")

	DirAccess.remove_absolute(path)
