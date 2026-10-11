extends Service
class_name ChatService

## ADR-043: Chat/Social — erste Umsetzung, zwei Kanäle.
##
## KANÄLE:
##   "global"  — an alle aktuell verbundenen Spieler, per
##               NetworkBridge.broadcast_to_all_peers() (ADR-042).
##   "whisper" — an genau einen Ziel-Spieler + Echo an den Absender, per
##               NetworkBridge.send_chat_message_for_player() (neu, dediziertes
##               RPC-Paar, analog send_economy_update_for_player()/
##               send_zone_update_for_peer() — bewusst KEIN Recycling eines
##               fachfremden Kanals, siehe NetworkBridge-Kommentar zu
##               report_domain_event()/domain_event_received(), das explizit
##               als Single-Consumer-Kanal für QuestService dokumentiert ist).
##
## AUTORITÄTS-LOKALE EMISSION (ADR-042-Konvention: kein Rundweg über das
## eigene RPC): on_send_message_confirmed() läuft nur auf der Autorität.
## - "global": message_received.emit() feuert dort IMMER lokal zusätzlich zum
##   Broadcast — der Host ist immer Teil des globalen Kanals.
## - "whisper": message_received.emit() feuert lokal NUR, wenn der Host
##   (NetworkBridge.get_local_player_id()) selbst Absender oder Ziel ist —
##   sonst würde ein Host, der an einem fremden Flüstern gar nicht beteiligt
##   ist, es trotzdem in seiner eigenen Chat-UI sehen. Ohne NetworkBridge
##   (Tier 1 / reine Business-Logik-Tests) gibt es dieses Dreiecksproblem
##   nicht — dort wird immer lokal emittiert.
##
## VALIDIERUNG: leere/nur-Whitespace-Nachrichten werden verworfen (kein
## Broadcast, kein Signal). Nachrichten werden auf MAX_MESSAGE_LENGTH
## gekappt (kein Fehler — matcht das im Projekt übliche "Menge %
## Verfügbares"-Clamping statt hartem Reject, siehe z. B.
## AuctionHouseService/InventorySystem). Einfaches Spam-Rate-Limit
## (MIN_INTERVAL_SEC pro Absender-player_id) — verwirft stillschweigend
## statt eines Fehler-Broadcasts, analog PickpocketServices Cooldown-Muster
## (ADR-039), nur ohne dessen `_failed`-Signal, weil ein verworfenes Chat-
## Retry für den Absender selbst keinen Sonderfall braucht (er sieht seine
## eigene Nachricht nur dann nicht im Feed — kein zusätzlicher Fehlerpfad
## nötig, im Unterschied zu einer fehlgeschlagenen Wirtschafts-Transaktion).
##
## BEWUSST NICHT TEIL DIESER RUNDE: kein Chat-Verlauf/Persistenz (rein
## transient — kein eigener Save-Key, kein `savesystem`-Dep), keine
## Wortfilter/serverseitige Moderation, keine Gruppen-/Party-Kanäle, kein
## UI-Panel (dieses ADR liefert nur die Service-/Netzwerk-Infrastruktur,
## analog wie `weather_changed`/`player_killed_by_player` zunächst auch nur
## als Signal existierten, bevor eine UI sie konsumierte — hier zusätzlich
## noch ohne UIContext-Eintrag, weil es noch keine UI gibt, die ihn
## bräuchte, analog PvPDeathLossService/PickpocketService).
##
## STUMMSCHALTEN (Round 100, ADR-044): mute_player()/unmute_player()/
## is_muted() — rein lokale, pro-Client Anzeige-Präferenz, KEIN
## autoritatives Moderations-Urteil und KEIN Netzwerk-Traffic (wer wen
## stummschaltet, geht niemanden sonst etwas an, auch nicht die Autorität).
## Gefilterte Nachrichten werden nirgends persistiert oder rückgängig
## gemacht — reine Anzeige-Unterdrückung auf message_received-Ebene, siehe
## _emit_if_not_muted(). Bewusst nicht persistiert (setzt bei jedem
## Sitzungsstart zurück) — konsistent mit dem "Chat ist transient"-Prinzip
## oben; für dauerhaftes Stummschalten über Sitzungen hinweg siehe
## ReportService (ADR-044), das eine autoritative Meldung persistiert, was
## etwas fachlich anderes ist als ein lokales Mute.

const LOG_CAT := "ChatService"

const CHANNEL_GLOBAL := "global"
const CHANNEL_WHISPER := "whisper"

const MAX_MESSAGE_LENGTH := 240
const MIN_INTERVAL_SEC := 1.0

## Emittiert eine vollständige Chat-Zeile — sowohl für lokale UI-Anzeige als
## auch (auf empfangenden Clients) nach Netzwerk-Empfang. `entry` enthält:
## message_id, sender_player_id, channel, text, target_player_id,
## timestamp_unix.
signal message_received(entry: Dictionary)

## Emittiert wenn eine Nachricht verworfen wurde (Rate-Limit oder leerer
## Text) — rein informativ für eine künftige UI ("Nachricht nicht
## gesendet"), kein Fehlerzustand, der irgendetwas rückgängig machen müsste.
signal message_rejected(sender_player_id: String, reason: String)

var _network: NetworkBridge = null

## Absender-player_id -> Unix-Zeit der letzten erfolgreich gesendeten
## Nachricht. Rein transient, kein Save-Key (siehe Klassenkommentar).
var _last_message_time: Dictionary = {}

## Round 100 (ADR-044): lokal stummgeschaltete player_ids. Rein transient,
## siehe Klassenkommentar "STUMMSCHALTEN".
var _muted_players: Dictionary = {}

func configure(_deps: ServiceDeps) -> void:
	AppLogger.log_info("ChatService initialisiert.", LOG_CAT)

func inject_network_bridge(network: NetworkBridge) -> void:
	_network = network
	_connect_network_signals()

func on_cleanup() -> void:
	if is_instance_valid(_network):
		if _network.broadcast_event_received.is_connected(_on_broadcast_event_received):
			_network.broadcast_event_received.disconnect(_on_broadcast_event_received)
		if _network.chat_message_received.is_connected(_on_chat_message_received):
			_network.chat_message_received.disconnect(_on_chat_message_received)
	_last_message_time.clear()
	_muted_players.clear()

## Round 100 (ADR-044): lokales Stummschalten — siehe Klassenkommentar.
func mute_player(player_id: String) -> void:
	_muted_players[player_id] = true

func unmute_player(player_id: String) -> void:
	_muted_players.erase(player_id)

func is_muted(player_id: String) -> bool:
	return _muted_players.has(player_id)

## Client-seitiger Einstiegspunkt: Nachricht senden wollen. Routet über
## NetworkBridge.send_chat_message() zur Autorität (RPC) NUR wenn dieser
## Prozess tatsächlich ein Nicht-Autoritäts-Client ist (Peer vorhanden UND
## nicht Server) — exakt derselbe Guard wie
## AuctionHouseService.request_list_item(). Auf der Autorität selbst (oder
## im reinen Tier-1-Test ohne Peer) direkt on_send_message_confirmed()
## aufrufen, kein unnötiger RPC-Rundweg zu sich selbst.
func request_send_message(sender_player_id: String, channel: String, text: String, target_player_id: String = "") -> void:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		_network.send_chat_message(channel, text, target_player_id, sender_player_id)
	else:
		on_send_message_confirmed(sender_player_id, channel, text, target_player_id)

## Autoritätsseitige Anwendung — läuft entweder direkt (Tier 1 / lokaler
## Host-Aufruf) oder als Ziel eines eingehenden RPCs von NetworkBridge.
func on_send_message_confirmed(sender_player_id: String, channel: String, text: String, target_player_id: String = "") -> void:
	if not _require_authority("on_send_message_confirmed"):
		return
	if sender_player_id.is_empty():
		return
	if channel != CHANNEL_GLOBAL and channel != CHANNEL_WHISPER:
		message_rejected.emit(sender_player_id, "unknown_channel")
		return
	if channel == CHANNEL_WHISPER and target_player_id.is_empty():
		message_rejected.emit(sender_player_id, "whisper_needs_target")
		return

	var clean_text := text.strip_edges()
	if clean_text.is_empty():
		message_rejected.emit(sender_player_id, "empty_message")
		return
	if clean_text.length() > MAX_MESSAGE_LENGTH:
		clean_text = clean_text.substr(0, MAX_MESSAGE_LENGTH)

	var now := _now()
	var last_time: float = float(_last_message_time.get(sender_player_id, -INF))
	if now - last_time < MIN_INTERVAL_SEC:
		message_rejected.emit(sender_player_id, "rate_limited")
		return
	_last_message_time[sender_player_id] = now

	var entry := {
		"message_id": UuidGen.generate_v4(),
		"sender_player_id": sender_player_id,
		"channel": channel,
		"text": clean_text,
		"target_player_id": target_player_id,
		"timestamp_unix": now,
	}

	match channel:
		CHANNEL_GLOBAL:
			_emit_if_not_muted(entry)
			if is_instance_valid(_network):
				_network.broadcast_to_all_peers("chat", entry)
		CHANNEL_WHISPER:
			var local_player_id := _network.get_local_player_id() if is_instance_valid(_network) else ""
			if not is_instance_valid(_network) or local_player_id == sender_player_id or local_player_id == target_player_id:
				_emit_if_not_muted(entry)
			if is_instance_valid(_network):
				_network.send_chat_message_for_player(sender_player_id, entry)
				if target_player_id != sender_player_id:
					_network.send_chat_message_for_player(target_player_id, entry)

## Round 100 (ADR-044): einziger Ort, an dem message_received tatsächlich
## feuert — filtert lokal stummgeschaltete Absender heraus, bevor eine
## künftige UI die Nachricht überhaupt sieht.
func _emit_if_not_muted(entry: Dictionary) -> void:
	if is_muted(String(entry.get("sender_player_id", ""))):
		return
	message_received.emit(entry)

## Client-Empfang: sowohl "global" (via broadcast_event_received, ADR-042)
## als auch "whisper" (via chat_message_received, dediziert) laufen hier
## zusammen — beide liefern dasselbe entry-Dictionary-Format.
func _on_broadcast_event_received(kind: String, payload: Dictionary) -> void:
	if kind != "chat":
		return
	_emit_if_not_muted(payload)

func _on_chat_message_received(payload: Dictionary) -> void:
	_emit_if_not_muted(payload)

func _connect_network_signals() -> void:
	if not is_instance_valid(_network):
		return
	if not _network.broadcast_event_received.is_connected(_on_broadcast_event_received):
		_network.broadcast_event_received.connect(_on_broadcast_event_received)
	if not _network.chat_message_received.is_connected(_on_chat_message_received):
		_network.chat_message_received.connect(_on_chat_message_received)

func _require_authority(caller: String) -> bool:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		AppLogger.log_error("%s: Aufruf auf Nicht-Autorität — verweigert." % caller, LOG_CAT)
		return false
	return true

func _now() -> float:
	return Time.get_unix_time_from_system()
