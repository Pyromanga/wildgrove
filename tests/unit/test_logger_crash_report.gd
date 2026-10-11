# res://tests/unit/test_logger_crash_report.gd
extends GutTest

## Unit-Tests für die Crash-Reporting-Erweiterung von AppLogger (ADR-045,
## Round 101 — "Telemetrie/Crash-Reporting", Crash-Report-Hälfte).
##
## WICHTIG: AppLogger.fatal() wird hier NIEMALS aufgerufen — es beendet den
## Prozess über get_tree().quit(1), was den kompletten Testlauf abbrechen
## würde. Getestet wird ausschließlich build_crash_report() (reine
## Dictionary-Konstruktion, kein Seiteneffekt) und write_crash_report()
## (Datei-I/O, aber ohne quit()).
##
## AppLogger ist ein echtes globales AutoLoad — vor/nach jedem Test wird
## der Ring-Puffer geleert (analog test_terminal_controller.gd), damit
## Tests sich nicht gegenseitig über den geteilten Zustand beeinflussen.

func before_each() -> void:
	AppLogger.flush_log_buffer()

func after_each() -> void:
	AppLogger.flush_log_buffer()

# ─────────────────────────────────────────────────────────────────────────────
# build_crash_report() — reine Datenkonstruktion
# ─────────────────────────────────────────────────────────────────────────────

func test_build_crash_report_contains_reason() -> void:
	var report := AppLogger.build_crash_report("test_reason_xyz")
	assert_eq(String(report["reason"]), "test_reason_xyz")

func test_build_crash_report_contains_expected_keys() -> void:
	var report := AppLogger.build_crash_report("r")
	for key in ["reason", "timestamp_unix", "timestamp_iso", "godot_version", "platform", "log_summary", "log_counts", "recent_errors", "recent_log_buffer"]:
		assert_true(report.has(key), "build_crash_report() muss den Schlüssel '%s' liefern." % key)

func test_build_crash_report_includes_recent_errors() -> void:
	AppLogger.log_error("ein absichtlicher Test-Fehler für den Crash-Report", "TestCategory")
	var report := AppLogger.build_crash_report("r")
	var errors: Array = report["recent_errors"]
	assert_true(errors.size() > 0, "Ein zuvor geloggter Fehler muss in recent_errors auftauchen.")

func test_build_crash_report_log_counts_reflect_current_session() -> void:
	AppLogger.log_error("noch ein absichtlicher Test-Fehler", "TestCategory")
	var report := AppLogger.build_crash_report("r")
	var counts: Dictionary = report["log_counts"]
	assert_true(int(counts.get(AppLogger.LogLevel.ERROR, 0)) > 0)

func test_build_crash_report_timestamp_is_recent() -> void:
	var before := Time.get_unix_time_from_system()
	var report := AppLogger.build_crash_report("r")
	var after := Time.get_unix_time_from_system()
	var ts: float = report["timestamp_unix"]
	assert_true(ts >= before - 1.0 and ts <= after + 1.0, "Zeitstempel muss ungefähr 'jetzt' sein.")

# ─────────────────────────────────────────────────────────────────────────────
# write_crash_report() — tatsächliches Datei-I/O
# ─────────────────────────────────────────────────────────────────────────────

func test_write_crash_report_creates_a_readable_json_file() -> void:
	var path := AppLogger.write_crash_report("integration_test_crash")
	assert_true(path.length() > 0, "write_crash_report() muss einen nicht-leeren Pfad zurückgeben.")
	assert_true(FileAccess.file_exists(path), "Die Crash-Report-Datei muss tatsächlich existieren.")

	var f := FileAccess.open(path, FileAccess.READ)
	assert_not_null(f)
	var text := f.get_as_text()
	f.close()

	var parsed: Variant = JSON.parse_string(text)
	assert_true(parsed is Dictionary, "Die Datei muss gültiges JSON enthalten.")
	assert_eq(String((parsed as Dictionary)["reason"]), "integration_test_crash")

	# Aufräumen — dieser Test soll keine Datei im Downloads-/user://-Ordner
	# hinterlassen.
	DirAccess.remove_absolute(path)
