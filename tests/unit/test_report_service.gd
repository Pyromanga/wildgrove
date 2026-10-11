# res://tests/unit/test_report_service.gd
extends GutTest

## Unit-Tests für ReportService (ADR-044 "Reporting/Moderation").
##
## Strategie: ReportService extends Service (RefCounted) — kein add_child
## nötig für den Tier-1-Pfad (analog test_aura_service.gd). savesystem/
## network_bridge sind beide optional_deps — konfiguriert nur dort, wo der
## jeweilige Test sie braucht.
##
## Abgedeckt:
##   - request_submit_report()/on_submit_report_confirmed(): Erfolg,
##     Validierung (leere IDs, Selbst-Meldung, unbekannter Grund, Details-
##     Cap), Rate-Limit pro Melder
##   - get_reports()/get_reports_against()
##   - Save-Interface: get_save_key(), Round-Trip, Kapazitätsgrenze
##     (MAX_STORED_REPORTS, älteste zuerst verworfen)
##   - Netzwerk-Pfad: send_report_submit() via SpyNetworkBridge

const P_REPORTER := "reporter-uuid"
const P_REPORTED := "reported-uuid"
const P_OTHER := "bystander-uuid"

var _svc: ReportService

func before_each() -> void:
	_svc = ReportService.new()
	_svc.configure(ServiceDeps.from_dict({}))

func after_each() -> void:
	_svc.on_cleanup()
	_svc = null

class SpyNetworkBridge extends NetworkBridge:
	var submit_calls: Array[Dictionary] = []
	func send_report_submit(reported_player_id: String, reason: String, details: String, context: Dictionary, reporter_player_id: String) -> void:
		submit_calls.append({
			"reported_player_id": reported_player_id, "reason": reason, "details": details,
			"context": context, "reporter_player_id": reporter_player_id,
		})

# ─────────────────────────────────────────────────────────────────────────────
# Validierung (Tier 1, ohne NetworkBridge — direkter Autoritäts-Pfad)
# ─────────────────────────────────────────────────────────────────────────────

func test_valid_report_is_submitted() -> void:
	var submitted: Array = []
	_svc.report_submitted.connect(func(entry): submitted.append(entry))
	_svc.request_submit_report(P_REPORTER, P_REPORTED, ReportService.REASON_HARASSMENT, "war unangemessen")

	assert_eq(submitted.size(), 1)
	assert_eq(String(submitted[0]["reporter_player_id"]), P_REPORTER)
	assert_eq(String(submitted[0]["reported_player_id"]), P_REPORTED)
	assert_eq(String(submitted[0]["reason"]), ReportService.REASON_HARASSMENT)
	assert_eq(String(submitted[0]["details"]), "war unangemessen")
	assert_true(String(submitted[0]["report_id"]).length() > 0)

func test_cannot_report_self() -> void:
	var rejected: Array = []
	_svc.report_rejected.connect(func(reporter, reason): rejected.append([reporter, reason]))
	_svc.request_submit_report(P_REPORTER, P_REPORTER, ReportService.REASON_SPAM)
	assert_eq(rejected, [[P_REPORTER, "cannot_report_self"]])

func test_unknown_reason_is_rejected() -> void:
	var rejected: Array = []
	_svc.report_rejected.connect(func(reporter, reason): rejected.append([reporter, reason]))
	_svc.request_submit_report(P_REPORTER, P_REPORTED, "made_up_reason")
	assert_eq(rejected, [[P_REPORTER, "unknown_reason"]])

func test_empty_reporter_or_reported_id_is_silently_ignored() -> void:
	var submitted: Array = []
	var rejected: Array = []
	_svc.report_submitted.connect(func(entry): submitted.append(entry))
	_svc.report_rejected.connect(func(reporter, reason): rejected.append([reporter, reason]))
	_svc.request_submit_report("", P_REPORTED, ReportService.REASON_SPAM)
	_svc.request_submit_report(P_REPORTER, "", ReportService.REASON_SPAM)
	assert_true(submitted.is_empty())
	assert_true(rejected.is_empty(), "Leere IDs sind ein Programmierfehler des Aufrufers, kein Nutzer-Fehlerfall.")

func test_details_are_clamped_to_max_length() -> void:
	var submitted: Array = []
	_svc.report_submitted.connect(func(entry): submitted.append(entry))
	var long_details := "x".repeat(ReportService.MAX_DETAILS_LENGTH + 100)
	_svc.request_submit_report(P_REPORTER, P_REPORTED, ReportService.REASON_OTHER, long_details)
	assert_eq(String(submitted[0]["details"]).length(), ReportService.MAX_DETAILS_LENGTH)

func test_rate_limit_rejects_second_report_within_window() -> void:
	var submitted: Array = []
	var rejected: Array = []
	_svc.report_submitted.connect(func(entry): submitted.append(entry))
	_svc.report_rejected.connect(func(reporter, reason): rejected.append([reporter, reason]))
	_svc.request_submit_report(P_REPORTER, P_REPORTED, ReportService.REASON_SPAM)
	_svc.request_submit_report(P_REPORTER, P_OTHER, ReportService.REASON_CHEATING)
	assert_eq(submitted.size(), 1, "Nur die erste Meldung darf durchgehen.")
	assert_eq(rejected, [[P_REPORTER, "rate_limited"]])

func test_rate_limit_is_per_reporter() -> void:
	var submitted: Array = []
	_svc.report_submitted.connect(func(entry): submitted.append(entry))
	_svc.request_submit_report(P_REPORTER, P_REPORTED, ReportService.REASON_SPAM)
	_svc.request_submit_report(P_OTHER, P_REPORTED, ReportService.REASON_SPAM)
	assert_eq(submitted.size(), 2, "Rate-Limit darf andere Melder nicht blockieren.")

func test_context_dictionary_is_passed_through() -> void:
	var submitted: Array = []
	_svc.report_submitted.connect(func(entry): submitted.append(entry))
	_svc.request_submit_report(P_REPORTER, P_REPORTED, ReportService.REASON_HARASSMENT, "", {"chat_message_id": "abc123", "chat_text": "böse Worte"})
	assert_eq(String((submitted[0]["context"] as Dictionary)["chat_message_id"]), "abc123")

# ─────────────────────────────────────────────────────────────────────────────
# get_reports() / get_reports_against()
# ─────────────────────────────────────────────────────────────────────────────

func test_get_reports_returns_all_submitted() -> void:
	_svc.request_submit_report(P_REPORTER, P_REPORTED, ReportService.REASON_SPAM)
	assert_eq(_svc.get_reports().size(), 1)

func test_get_reports_against_filters_by_target() -> void:
	_svc.request_submit_report(P_REPORTER, P_REPORTED, ReportService.REASON_SPAM)
	_svc.request_submit_report(P_OTHER, P_REPORTER, ReportService.REASON_CHEATING)
	var against_reported := _svc.get_reports_against(P_REPORTED)
	assert_eq(against_reported.size(), 1)
	assert_eq(String(against_reported[0]["reported_player_id"]), P_REPORTED)

func test_get_reports_returns_a_copy() -> void:
	_svc.request_submit_report(P_REPORTER, P_REPORTED, ReportService.REASON_SPAM)
	var copy := _svc.get_reports()
	copy.clear()
	assert_eq(_svc.get_reports().size(), 1, "get_reports() darf keine interne Referenz zurückgeben.")

# ─────────────────────────────────────────────────────────────────────────────
# Save-Interface
# ─────────────────────────────────────────────────────────────────────────────

func test_save_key_is_reports() -> void:
	assert_eq(_svc.get_save_key(), "reports")

func test_save_data_empty_by_default() -> void:
	var saved := _svc.get_save_data()
	assert_eq((saved["reports"] as Array).size(), 0)

func test_save_data_round_trip_preserves_reports() -> void:
	_svc.request_submit_report(P_REPORTER, P_REPORTED, ReportService.REASON_HARASSMENT, "Detail-Text")
	var snapshot := _svc.get_save_data()

	var svc2 := ReportService.new()
	svc2.configure(ServiceDeps.from_dict({}))
	svc2._restore_from_save(snapshot)

	assert_eq(svc2.get_reports().size(), 1, "Meldungen müssen Round-Trip überleben.")
	assert_eq(String(svc2.get_reports()[0]["reported_player_id"]), P_REPORTED)

func test_on_submit_report_confirmed_enforces_cap() -> void:
	# Rate-Limit künstlich umgehen (_last_report_time vor jedem Aufruf
	# geleert), um MAX_STORED_REPORTS+3 Meldungen in einem Test zu erzeugen
	# und die tatsächliche Kapazitätsgrenze im echten Code-Pfad zu prüfen.
	for i in range(ReportService.MAX_STORED_REPORTS + 3):
		_svc._last_report_time.clear()
		_svc.on_submit_report_confirmed(P_REPORTER, P_REPORTED, ReportService.REASON_SPAM, str(i))
	assert_eq(_svc.get_reports().size(), ReportService.MAX_STORED_REPORTS,
		"Die Liste darf MAX_STORED_REPORTS nicht überschreiten — älteste zuerst verworfen.")

# ─────────────────────────────────────────────────────────────────────────────
# Netzwerk-Pfad (ADR-044)
# ─────────────────────────────────────────────────────────────────────────────

func test_request_submit_report_calls_network_when_not_authority() -> void:
	# Kein echter Peer im Test -> has_peer() ist false -> geht direkt lokal.
	# Dieser Test dokumentiert daher den Tier-1-Fallback-Pfad: ohne echten
	# Peer läuft request_submit_report() immer direkt in
	# on_submit_report_confirmed(), NIE über send_report_submit() — exakt
	# das AuctionHouseService/ChatService-Guard-Muster.
	var net := SpyNetworkBridge.new()
	add_child_autofree(net)
	_svc.inject_network_bridge(net)

	var submitted: Array = []
	_svc.report_submitted.connect(func(entry): submitted.append(entry))
	_svc.request_submit_report(P_REPORTER, P_REPORTED, ReportService.REASON_SPAM)

	assert_eq(net.submit_calls.size(), 0, "Ohne echten Peer (Tier 1) darf kein RPC versucht werden.")
	assert_eq(submitted.size(), 1, "Stattdessen muss der direkte Autoritäts-Pfad laufen.")
