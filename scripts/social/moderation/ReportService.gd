extends Service
class_name ReportService

## ADR-044: Reporting/Moderation — erste Umsetzung ("Reporting-/
## Moderationswerkzeug für Multiplayer-Verhalten", seit Round 53 offen).
##
## Zwei unabhängige Bausteine, bewusst getrennt (siehe ADR-044):
##   1. ReportService (dieser Service) — Spieler meldet Spieler an die
##      Autorität, persistiert für spätere Durchsicht. `context` ist ein
##      opakes Dictionary — z. B. `{"chat_message_id": ..., "chat_text": ...}`
##      beim Melden einer Chat-Nachricht — ReportService kennt ChatService
##      NICHT, keine Kopplung zwischen den beiden Services.
##   2. Lokales Stummschalten — lebt bewusst in ChatService selbst
##      (`mute_player()`/`unmute_player()`/`is_muted()`), nicht hier: Mute
##      ist eine rein lokale Anzeige-Präferenz des jeweiligen Clients, kein
##      autoritatives Moderations-Urteil, braucht also weder Netzwerk noch
##      dieses Service. Siehe ChatService.gd-Kommentar für die Begründung.
##
## PERSISTENZ: Meldungen werden gespeichert (SAVE_KEY = "reports") — anders
## als Chat (bewusst transient) müssen Meldungen eine Sitzung überdauern,
## damit sie überhaupt durchsehbar sind. `MAX_STORED_REPORTS` begrenzt die
## Liste (älteste zuerst verworfen) — kein unbegrenztes Wachstum des Saves.
##
## VALIDIERUNG: `reason` muss aus `VALID_REASONS` stammen (kein Freitext-
## Grund — macht spätere Auswertung/Filterung sinnvoll möglich). `details`
## wird auf MAX_DETAILS_LENGTH gekappt (Clamp-statt-Reject-Prinzip, wie bei
## ChatService). Rate-Limit pro Melder (MIN_INTERVAL_SEC) gegen Report-Spam
## — deutlich großzügiger als Chat, weil eine legitime Meldung selten ist,
## Report-Spam aber selbst ein Missbrauchsvektor wäre.
##
## BEWUSST NICHT TEIL DIESER RUNDE: kein Review-/Admin-UI (dieses ADR
## liefert nur die Service-/Speicher-Infrastruktur, analog Chat/PvP-Kill-
## Feed in vorigen Runden), keine automatischen Konsequenzen (Bans/Kicks/
## Mutes durch die Autorität) — eine Meldung wird nur gespeichert, nicht
## ausgewertet, kein `UIContext`-Eintrag (noch keine UI, die ihn bräuchte).

const LOG_CAT := "ReportService"
const SAVE_KEY := "reports"

const REASON_HARASSMENT := "harassment"
const REASON_SPAM := "spam"
const REASON_CHEATING := "cheating"
const REASON_INAPPROPRIATE_NAME := "inappropriate_name"
const REASON_OTHER := "other"
const VALID_REASONS: Array[String] = [
	REASON_HARASSMENT, REASON_SPAM, REASON_CHEATING, REASON_INAPPROPRIATE_NAME, REASON_OTHER,
]

const MAX_DETAILS_LENGTH := 500
const MIN_INTERVAL_SEC := 30.0
const MAX_STORED_REPORTS := 500

## Emittiert nach erfolgreicher Speicherung einer Meldung — sowohl auf der
## Autorität (immer, es gibt kein Bystander-Problem wie bei Chat-Whisper,
## Meldungen sind ohnehin nie an andere Spieler sichtbar) als auch für den
## meldenden Client selbst als Bestätigung (siehe request_submit_report()).
signal report_submitted(entry: Dictionary)

signal report_rejected(reporter_player_id: String, reason: String)

var _network: NetworkBridge = null
var _save_system: SaveSystem = null

## Chronologische Liste aller gespeicherten Meldungen (Dictionaries).
var _reports: Array = []

## Melder-player_id -> Unix-Zeit der letzten erfolgreich gespeicherten Meldung.
var _last_report_time: Dictionary = {}

func configure(deps: ServiceDeps) -> void:
	_network     = deps.get_optional(ServiceKeys.NETWORK_BRIDGE) as NetworkBridge
	_save_system = deps.get_optional(ServiceKeys.SAVE_SYSTEM)    as SaveSystem

	if _save_system:
		_save_system.register_save_provider(self)
		var saved: Variant = _save_system.get_state_for(SAVE_KEY)
		if saved is Dictionary and not (saved as Dictionary).is_empty():
			_restore_from_save(saved)
	else:
		AppLogger.log_error("Abhängigkeit 'savesystem' fehlt!", LOG_CAT)

	AppLogger.log_info("ReportService initialisiert (%d gespeicherte Meldungen)." % _reports.size(), LOG_CAT)

func inject_network_bridge(network: NetworkBridge) -> void:
	_network = network

func on_cleanup() -> void:
	pass

## Client-seitiger Einstiegspunkt. Derselbe Guard wie
## AuctionHouseService.request_list_item()/ChatService.request_send_message().
func request_submit_report(reporter_player_id: String, reported_player_id: String, reason: String, details: String = "", context: Dictionary = {}) -> void:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		_network.send_report_submit(reported_player_id, reason, details, context, reporter_player_id)
	else:
		on_submit_report_confirmed(reporter_player_id, reported_player_id, reason, details, context)

func on_submit_report_confirmed(reporter_player_id: String, reported_player_id: String, reason: String, details: String = "", context: Dictionary = {}) -> void:
	if not _require_authority("on_submit_report_confirmed"):
		return
	if reporter_player_id.is_empty() or reported_player_id.is_empty():
		return
	if reported_player_id == reporter_player_id:
		report_rejected.emit(reporter_player_id, "cannot_report_self")
		return
	if not (reason in VALID_REASONS):
		report_rejected.emit(reporter_player_id, "unknown_reason")
		return

	var now := _now()
	var last_time: float = float(_last_report_time.get(reporter_player_id, -INF))
	if now - last_time < MIN_INTERVAL_SEC:
		report_rejected.emit(reporter_player_id, "rate_limited")
		return
	_last_report_time[reporter_player_id] = now

	var clean_details := details.strip_edges()
	if clean_details.length() > MAX_DETAILS_LENGTH:
		clean_details = clean_details.substr(0, MAX_DETAILS_LENGTH)

	var entry := {
		"report_id": UuidGen.generate_v4(),
		"reporter_player_id": reporter_player_id,
		"reported_player_id": reported_player_id,
		"reason": reason,
		"details": clean_details,
		"context": context,
		"timestamp_unix": now,
	}
	_reports.append(entry)
	if _reports.size() > MAX_STORED_REPORTS:
		_reports.pop_front()

	report_submitted.emit(entry)
	AppLogger.log_info(
		"Meldung gespeichert: '%s' meldet '%s' (%s)." % [reporter_player_id, reported_player_id, reason],
		LOG_CAT
	)

## Für künftige Review-Tooling (kein UI in dieser Runde). Gibt eine flache
## Kopie zurück — Aufrufer dürfen die interne Liste nicht mutieren.
func get_reports() -> Array:
	return _reports.duplicate(true)

func get_reports_against(reported_player_id: String) -> Array:
	return _reports.filter(func(e): return e.get("reported_player_id", "") == reported_player_id)

# ─────────────────────────────────────────────
# Save-Interface (analog AuraService/PvPService)
# ─────────────────────────────────────────────

func get_save_key() -> String:
	return SAVE_KEY

func get_save_data() -> Dictionary:
	return {"reports": _reports}

func _restore_from_save(saved: Dictionary) -> void:
	if saved.get("reports") is Array:
		_reports = saved["reports"]

func _require_authority(caller: String) -> bool:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		AppLogger.log_error("%s: Aufruf auf Nicht-Autorität — verweigert." % caller, LOG_CAT)
		return false
	return true

func _now() -> float:
	return Time.get_unix_time_from_system()
