extends Service
class_name TradeService

## TradeService — ADR-035: synchroner Spieler-zu-Spieler-Handel (Handshake-Teil,
## Gegenstück zu AuctionHouseService für den asynchronen Teil).
##
## EINSTIEGSPUNKT bewusst NICHT über eine eigene Netzwerk-Route, sondern über
## die bereits bestehende Interaktions-Pipeline (ADR-020/023) — exakt dieselbe,
## über die PvP-Angriffe laufen (siehe PlayerAttack.gd/PlayerTrade.gd,
## Player._on_interacted()): ein "trade_request"-InteractableComponent auf dem
## Ziel-Spieler-Node, dessen Vervollständigung bei Nicht-Autorität automatisch
## per RPC an die Autorität weitergereicht wird (InteractableComponent.
## _handle_completion() → WorldService.request_entity_interaction()). Die
## Autorität ruft dort auf ihrer eigenen (echten) Kopie des Ziel-Player-Nodes
## erneut _on_interacted() auf, diesmal mit is_multiplayer_authority() == true,
## und mutiert direkt über on_invite_confirmed() — kein separater
## request_invite()-RPC-Pfad nötig, dieselbe Begründung wie bei PvP-Treffern
## (CombatSystem.resolve_pvp_hit()).
##
## AB DEM OFFENEN HANDELS-PANEL (Angebot ändern/Ready/Bestätigen/Abbrechen)
## läuft es dagegen wie Bank/Shop: die UI läuft auf dem Peer des jeweiligen
## Spielers, nicht zwingend der Autorität — deshalb request_/on_*_confirmed()
## mit eigenem NetworkBridge-Routing (analog BankService/ShopService, NICHT wie
## InventorySystem/CurrencyService seit deren Root-Cause-Fix Round 45).
##
## SCAM-SCHUTZ (ADR-035 "kritisch"): jede Änderung am Angebot NACH einer
## Ready-/Bestätigungs-Markierung setzt beide Markierungen für BEIDE Seiten
## zurück. Zwei-Stufen-Bestätigung: erst müssen beide "ready" sein, bevor
## überhaupt eine "finale Bestätigung" möglich ist — das UI zeigt zwischen
## diesen beiden Stufen das exakt finale Angebot beider Seiten an.
##
## ESCROW: bewusst KEINS. Anders als beim Auktionshaus (asynchron, Items
## müssen während der gesamten Auktionslaufzeit dem Verkäufer entzogen sein)
## ist der Handshake-Handel synchron — Items verlassen das Inventar erst beim
## atomaren Swap in _execute_trade(). Zwischen Angebot und Swap gilt dieselbe
## "Absicht statt Wert"-Regel wie überall (ADR-004/Round-45-Lehre):
## _execute_trade() validiert beide Angebote GEGEN DEN AKTUELLEN Bestand neu,
## bevor irgendetwas mutiert wird — hat ein Spieler in der Zwischenzeit z.B.
## das angebotene Item in die Bank gelegt, bricht der Handel sauber ab statt
## mit falschem Zustand fortzufahren.
##
## Keine Persistenz — Sessions sind reine Laufzeit-Verhandlungen, kein
## ISaveProvider nötig (verglichen mit AuctionHouseService, dessen Listings
## über Server-Neustarts hinweg gültig bleiben müssen).

signal invite_received(to_player_id: String, from_player_id: String)
signal invite_declined(player_id: String)
signal session_started(session_id: String, player_a: String, player_b: String)
signal session_updated(session_id: String)
signal session_cancelled(session_id: String, reason: String)
signal trade_completed(session_id: String, player_a: String, player_b: String)

## ADR-050 Phase 2 (Round 113): das ursprünglich generische `transaction_failed`
## ist nach scripts/economy/trading/TradeEvents.gd (EventBus-Namespace `trade`)
## migriert — jetzt eindeutig `trade_transaction_failed`, siehe
## TradeEvents.gd-Klassenkommentar.

const LOG_CAT := "Trade"

var _inventory: InventorySystem = null
var _currency:  CurrencyService = null
var _network:   NetworkBridge   = null
var _bus:       IEventBus       = null

## to_player_id (String) -> from_player_id (String). Bewusst nur EINE
## eingehende Einladung pro Ziel-Spieler gleichzeitig — eine zweite Einladung
## an denselben Spieler überschreibt die erste (kein Warteschlangen-Bedarf für
## diesen Umfang).
var _pending_invites: Dictionary = {}

## session_id (String) -> Dictionary { player_a, player_b, offer_a, offer_b,
## ready_a, ready_b, confirmed_a, confirmed_b }. offer_x: { items: {item_id:
## quantity(int)}, gold: int }.
var _sessions: Dictionary = {}

## player_id -> session_id — verhindert, dass ein Spieler gleichzeitig in
## mehr als einer aktiven Session steckt, und erlaubt schnelles Lookup fürs UI.
var _active_session_of: Dictionary = {}

# ─────────────────────────────────────────────
# Phase 4: Configure (DI)
# ─────────────────────────────────────────────

func configure(deps: ServiceDeps) -> void:
	_inventory = deps.require(ServiceKeys.INVENTORY) as InventorySystem
	_currency  = deps.require(ServiceKeys.CURRENCY)  as CurrencyService
	_network   = deps.get_optional(ServiceKeys.NETWORK_BRIDGE) as NetworkBridge
	_bus       = deps.get_optional(ServiceKeys.EVENT_BUS)      as IEventBus
	_connect_economy_sync()
	AppLogger.log_info("TradeService initialisiert.", LOG_CAT)

func inject_network_bridge(network: NetworkBridge) -> void:
	_network = network
	_connect_economy_sync()

func _connect_economy_sync() -> void:
	if is_instance_valid(_network) and not _network.economy_state_received.is_connected(_on_economy_state_received):
		_network.economy_state_received.connect(_on_economy_state_received)

func on_cleanup() -> void:
	if is_instance_valid(_network) and _network.economy_state_received.is_connected(_on_economy_state_received):
		_network.economy_state_received.disconnect(_on_economy_state_received)

# ─────────────────────────────────────────────
# Client-Empfang (R-7/ADR-022-Muster, kind == "trade")
# ─────────────────────────────────────────────

func _on_economy_state_received(kind: String, payload: Dictionary) -> void:
	if kind != "trade":
		return
	match String(payload.get("event", "")):
		"invite_received":
			var from_id: String = String(payload.get("from", ""))
			var to_id: String   = String(payload.get("to", ""))
			_pending_invites[to_id] = from_id
			invite_received.emit(to_id, from_id)
		"invite_declined":
			invite_declined.emit(String(payload.get("player_id", "")))
		"session_update":
			var session: Dictionary = payload.get("session", {})
			var sid: String = String(session.get("session_id", ""))
			if sid.is_empty():
				return
			var is_new := not _sessions.has(sid)
			_sessions[sid] = session
			_active_session_of[String(session.get("player_a", ""))] = sid
			_active_session_of[String(session.get("player_b", ""))] = sid
			if is_new:
				session_started.emit(sid, session.get("player_a", ""), session.get("player_b", ""))
			session_updated.emit(sid)
		"session_cancelled":
			var csid: String = String(payload.get("session_id", ""))
			_forget_session(csid)
			session_cancelled.emit(csid, String(payload.get("reason", "")))
		"trade_completed":
			var tsid: String = String(payload.get("session_id", ""))
			var pa: String   = String(payload.get("player_a", ""))
			var pb: String   = String(payload.get("player_b", ""))
			_forget_session(tsid)
			trade_completed.emit(tsid, pa, pb)
		"transaction_failed":
			if is_instance_valid(_bus):
				_bus.trade().emit_trade_transaction_failed(
					String(payload.get("player_id", "")),
					String(payload.get("session_id", "")),
					String(payload.get("reason", ""))
				)

func _forget_session(session_id: String) -> void:
	var session: Dictionary = _sessions.get(session_id, {})
	if session.has("player_a"):
		_active_session_of.erase(String(session["player_a"]))
	if session.has("player_b"):
		_active_session_of.erase(String(session["player_b"]))
	_sessions.erase(session_id)

# ─────────────────────────────────────────────
# Öffentliche API — Abfrage
# ─────────────────────────────────────────────

func get_pending_invite_for(player_id: String) -> String:
	return String(_pending_invites.get(player_id, ""))

func get_session_for(player_id: String) -> Dictionary:
	var sid: String = String(_active_session_of.get(player_id, ""))
	if sid.is_empty():
		return {}
	return _sessions.get(sid, {})

# ─────────────────────────────────────────────
# Einladung — Autoritäts-Einstiegspunkt, siehe Klassenkommentar oben.
# Wird NUR von Player._on_interacted() (bereits auf der Autorität laufend)
# aufgerufen, kein request_-Gegenstück nötig.
# ─────────────────────────────────────────────

func on_invite_confirmed(from_player_id: String, to_player_id: String) -> void:
	if not _require_authority("on_invite_confirmed"):
		return
	if from_player_id.is_empty() or to_player_id.is_empty() or from_player_id == to_player_id:
		return
	if _active_session_of.has(from_player_id) or _active_session_of.has(to_player_id):
		AppLogger.log_warn(
			"on_invite_confirmed: '%s' oder '%s' ist bereits in einer aktiven Session." % [from_player_id, to_player_id],
			LOG_CAT
		)
		return
	_pending_invites[to_player_id] = from_player_id
	AppLogger.log_debug("Handelseinladung: '%s' → '%s'." % [from_player_id, to_player_id], LOG_CAT)
	_send_to(from_player_id, {"event": "invite_received", "from": from_player_id, "to": to_player_id})
	_send_to(to_player_id, {"event": "invite_received", "from": from_player_id, "to": to_player_id})
	invite_received.emit(to_player_id, from_player_id)

# ─────────────────────────────────────────────
# Ab hier: UI-initiierte Aktionen — request_/on_*_confirmed mit eigenem
# NetworkBridge-Routing (analog BankService), da die UI auf dem Peer des
# jeweiligen Spielers läuft.
# ─────────────────────────────────────────────

func request_respond_invite(player_id: String, accept: bool) -> void:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		_network.send_trade_respond_invite(accept, player_id)
	else:
		on_invite_response_confirmed(player_id, accept)

func on_invite_response_confirmed(player_id: String, accept: bool) -> void:
	if not _require_authority("on_invite_response_confirmed"):
		return
	var from_id: String = String(_pending_invites.get(player_id, ""))
	if from_id.is_empty():
		return
	_pending_invites.erase(player_id)

	if not accept:
		_send_to(from_id, {"event": "invite_declined", "player_id": player_id})
		_send_to(player_id, {"event": "invite_declined", "player_id": player_id})
		invite_declined.emit(player_id)
		return

	if _active_session_of.has(from_id) or _active_session_of.has(player_id):
		# Einer der beiden ist inzwischen anderweitig beschäftigt — sauber abbrechen.
		_send_to(from_id, {"event": "invite_declined", "player_id": player_id})
		_send_to(player_id, {"event": "invite_declined", "player_id": player_id})
		invite_declined.emit(player_id)
		return

	var session_id := UuidGen.generate_v4()
	var session := _make_session(session_id, from_id, player_id)
	_sessions[session_id] = session
	_active_session_of[from_id]   = session_id
	_active_session_of[player_id] = session_id
	session_started.emit(session_id, from_id, player_id)
	_push_session(session)

func request_update_offer(player_id: String, session_id: String, items: Dictionary, gold: int) -> void:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		_network.send_trade_update_offer(session_id, items, gold, player_id)
	else:
		on_offer_updated_confirmed(player_id, session_id, items, gold)

func on_offer_updated_confirmed(player_id: String, session_id: String, items: Dictionary, gold: int) -> void:
	if not _require_authority("on_offer_updated_confirmed"):
		return
	var session: Dictionary = _sessions.get(session_id, {})
	var side := _side_of(session, player_id)
	if side.is_empty():
		return
	if gold < 0:
		if is_instance_valid(_bus):
			_bus.trade().emit_trade_transaction_failed(player_id, session_id, "invalid_gold_amount")
		return
	for item_id in items:
		if int(items[item_id]) <= 0:
			if is_instance_valid(_bus):
				_bus.trade().emit_trade_transaction_failed(player_id, session_id, "invalid_item_quantity")
			return

	session["offer_" + side] = {"items": (items as Dictionary).duplicate(), "gold": gold}
	_reset_confirmation(session)
	_push_session(session)

func request_set_ready(player_id: String, session_id: String, ready: bool) -> void:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		_network.send_trade_set_ready(session_id, ready, player_id)
	else:
		on_ready_confirmed(player_id, session_id, ready)

func on_ready_confirmed(player_id: String, session_id: String, ready: bool) -> void:
	if not _require_authority("on_ready_confirmed"):
		return
	var session: Dictionary = _sessions.get(session_id, {})
	var side := _side_of(session, player_id)
	if side.is_empty():
		return
	session["ready_" + side] = ready
	if not ready:
		session["confirmed_" + side] = false
	_push_session(session)

func request_set_confirmed(player_id: String, session_id: String, confirmed: bool) -> void:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		_network.send_trade_set_confirmed(session_id, confirmed, player_id)
	else:
		on_confirm_confirmed(player_id, session_id, confirmed)

func on_confirm_confirmed(player_id: String, session_id: String, confirmed: bool) -> void:
	if not _require_authority("on_confirm_confirmed"):
		return
	var session: Dictionary = _sessions.get(session_id, {})
	var side := _side_of(session, player_id)
	if side.is_empty():
		return
	if confirmed and not (session.get("ready_a", false) and session.get("ready_b", false)):
		if is_instance_valid(_bus):
			_bus.trade().emit_trade_transaction_failed(player_id, session_id, "not_ready")
		return

	session["confirmed_" + side] = confirmed
	if session.get("confirmed_a", false) and session.get("confirmed_b", false):
		_execute_trade(session)
	else:
		_push_session(session)

func request_cancel(player_id: String, session_id: String) -> void:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		_network.send_trade_cancel(session_id, player_id)
	else:
		on_cancel_confirmed(player_id, session_id)

func on_cancel_confirmed(player_id: String, session_id: String) -> void:
	if not _require_authority("on_cancel_confirmed"):
		return
	var session: Dictionary = _sessions.get(session_id, {})
	if _side_of(session, player_id).is_empty():
		return
	_forget_session(session_id)
	session_cancelled.emit(session_id, "cancelled_by_player")
	_send_to(String(session["player_a"]), {"event": "session_cancelled", "session_id": session_id, "reason": "cancelled_by_player"})
	_send_to(String(session["player_b"]), {"event": "session_cancelled", "session_id": session_id, "reason": "cancelled_by_player"})

# ─────────────────────────────────────────────
# Atomarer Swap
# ─────────────────────────────────────────────

func _execute_trade(session: Dictionary) -> void:
	var session_id: String = String(session["session_id"])
	var a: String = String(session["player_a"])
	var b: String = String(session["player_b"])
	var offer_a: Dictionary = session["offer_a"]
	var offer_b: Dictionary = session["offer_b"]

	# Tier-3-Prinzip ("Server vertraut niemandem"): Neuvalidierung gegen den
	# AKTUELLEN Bestand, nicht gegen den Stand beim letzten Angebots-Update —
	# verhindert Bait-and-Switch über die Zeitspanne zwischen Ready/Bestätigen
	# und diesem Moment (z.B. Item zwischenzeitlich verbraucht/verkauft).
	if not _validate_offer(a, offer_a) or not _validate_offer(b, offer_b):
		_forget_session(session_id)
		session_cancelled.emit(session_id, "offer_no_longer_valid")
		_send_to(a, {"event": "session_cancelled", "session_id": session_id, "reason": "offer_no_longer_valid"})
		_send_to(b, {"event": "session_cancelled", "session_id": session_id, "reason": "offer_no_longer_valid"})
		return

	if not _remove_offer(a, offer_a):
		_fail_execution(session_id, a, b, "remove_failed")
		return
	if not _remove_offer(b, offer_b):
		_add_offer(a, offer_a)  # Rollback A
		_fail_execution(session_id, a, b, "remove_failed")
		return

	if not _add_offer(b, offer_a):
		# Rollback beider Entnahmen
		_add_offer(a, offer_a)
		_add_offer(b, offer_b)
		_fail_execution(session_id, a, b, "recipient_cannot_receive")
		return
	if not _add_offer(a, offer_b):
		# b hat offer_a bereits erhalten — das zurückdrehen, dann beide Entnahmen rückgängig machen.
		_remove_offer(b, offer_a)
		_add_offer(a, offer_a)
		_add_offer(b, offer_b)
		_fail_execution(session_id, a, b, "recipient_cannot_receive")
		return

	_forget_session(session_id)
	trade_completed.emit(session_id, a, b)
	_send_to(a, {"event": "trade_completed", "session_id": session_id, "player_a": a, "player_b": b})
	_send_to(b, {"event": "trade_completed", "session_id": session_id, "player_a": a, "player_b": b})
	AppLogger.log_info("Handel abgeschlossen: '%s' ↔ '%s' (Session %s)." % [a, b, session_id], LOG_CAT)

func _fail_execution(session_id: String, a: String, b: String, reason: String) -> void:
	_forget_session(session_id)
	if is_instance_valid(_bus):
		_bus.trade().emit_trade_transaction_failed(a, session_id, reason)
		_bus.trade().emit_trade_transaction_failed(b, session_id, reason)
	_send_to(a, {"event": "transaction_failed", "player_id": a, "session_id": session_id, "reason": reason})
	_send_to(b, {"event": "transaction_failed", "player_id": b, "session_id": session_id, "reason": reason})
	AppLogger.log_error("Handel fehlgeschlagen ('%s'): '%s' ↔ '%s' (Session %s)." % [reason, a, b, session_id], LOG_CAT)

func _validate_offer(player_id: String, offer: Dictionary) -> bool:
	var gold: int = int(offer.get("gold", 0))
	if gold > 0 and not _currency.has_gold(player_id, gold):
		return false
	var items: Dictionary = offer.get("items", {})
	for item_id in items:
		if not _inventory.has_item(item_id, player_id, int(items[item_id])):
			return false
	return true

func _remove_offer(player_id: String, offer: Dictionary) -> bool:
	var gold: int = int(offer.get("gold", 0))
	if gold > 0 and not _currency.request_remove_gold(player_id, gold):
		return false
	var items: Dictionary = offer.get("items", {})
	var removed: Array[String] = []
	for item_id in items:
		if not _inventory.remove_item(item_id, player_id, int(items[item_id])):
			# Teilweise entnommene Items dieses Aufrufs zurückgeben, dann Gold zurückbuchen.
			for done_id in removed:
				_inventory.request_add_item(done_id, player_id, int(items[done_id]))
			if gold > 0:
				_currency.request_add_gold(player_id, gold)
			return false
		removed.append(item_id)
	return true

func _add_offer(player_id: String, offer: Dictionary) -> bool:
	var gold: int = int(offer.get("gold", 0))
	if gold > 0 and not _currency.request_add_gold(player_id, gold):
		return false
	var items: Dictionary = offer.get("items", {})
	for item_id in items:
		if not _inventory.request_add_item(item_id, player_id, int(items[item_id])):
			return false
	return true

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _make_session(session_id: String, player_a: String, player_b: String) -> Dictionary:
	return {
		"session_id":   session_id,
		"player_a":     player_a,
		"player_b":     player_b,
		"offer_a":      {"items": {}, "gold": 0},
		"offer_b":      {"items": {}, "gold": 0},
		"ready_a":      false,
		"ready_b":      false,
		"confirmed_a":  false,
		"confirmed_b":  false,
	}

func _reset_confirmation(session: Dictionary) -> void:
	session["ready_a"]     = false
	session["ready_b"]     = false
	session["confirmed_a"] = false
	session["confirmed_b"] = false

## Gibt "a"/"b" zurück je nachdem welcher Seite player_id in dieser Session
## entspricht, oder "" wenn er nicht Teilnehmer ist (auch wenn session leer ist).
func _side_of(session: Dictionary, player_id: String) -> String:
	if session.is_empty():
		return ""
	if session.get("player_a", "") == player_id:
		return "a"
	if session.get("player_b", "") == player_id:
		return "b"
	return ""

func _push_session(session: Dictionary) -> void:
	var payload := {"event": "session_update", "session": session}
	_send_to(String(session["player_a"]), payload)
	_send_to(String(session["player_b"]), payload)
	session_updated.emit(String(session["session_id"]))

func _send_to(player_id: String, payload: Dictionary) -> void:
	if is_instance_valid(_network):
		_network.send_economy_update_for_player(player_id, "trade", payload)

func _require_authority(caller: String) -> bool:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		AppLogger.log_error("%s: Aufruf auf Nicht-Autorität — verweigert." % caller, LOG_CAT)
		return false
	return true
