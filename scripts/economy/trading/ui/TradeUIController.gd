class_name TradeUIController
extends Node

## TradeUIController — Logik fürs Handshake-Handel-Panel (ADR-035). Analog
## BankUIController/ShopUIController, mit einem strukturellen Unterschied:
## es gibt kein "*_opened"-Signal, das den NPC-Umweg macht (siehe
## UIEvents.gd-Klassenkommentar) — dieser Controller abonniert TradeService
## direkt (invite_received/session_started/session_updated/...).
##
## SINGLE SOURCE OF TRUTH: der Controller hält KEINE eigene Kopie des
## Angebots. Jede Mutation (Item hinzufügen/entfernen, Gold setzen) liest den
## aktuellen Session-Stand über TradeService.get_session_for() und sendet
## darauf aufbauend das vollständige neue Angebot per request_update_offer()
## — exakt wie TradeService.on_offer_updated_confirmed() es serverseitig auch
## erwartet (voller Ersatz, kein Patch). Das verhindert Client/Server-Drift
## und spiegelt die "Absicht statt Wert"-Regel (ADR-004): die UI behauptet
## nie einen Zustand, sie liest ihn.

var _visuals: TradeVisuals
var _ctx: IUIContext

## Merkt sich für wen zuletzt eine Einladung angezeigt wurde, um
## invite_declined() korrekt nur das eigene Popup zu schließen.
var _pending_invite_from: String = ""

func setup(visuals: TradeVisuals, ctx: IUIContext) -> void:
	_visuals = visuals
	_ctx     = ctx

	_visuals.invite_accept_requested.connect(_on_invite_accept)
	_visuals.invite_decline_requested.connect(_on_invite_decline)
	_visuals.close_requested.connect(_on_close_requested)
	_visuals.add_item_requested.connect(_on_add_item)
	_visuals.remove_item_requested.connect(_on_remove_item)
	_visuals.set_gold_requested.connect(_on_set_gold)
	_visuals.ready_toggled.connect(_on_ready_toggled)
	_visuals.confirm_pressed.connect(_on_confirm_pressed)

	var trade := _ctx.get_trade_service()
	if is_instance_valid(trade):
		trade.invite_received.connect(_on_invite_received)
		trade.invite_declined.connect(_on_invite_declined)
		trade.session_started.connect(_on_session_started)
		trade.session_updated.connect(_on_session_updated)
		trade.session_cancelled.connect(_on_session_cancelled)
		trade.trade_completed.connect(_on_trade_completed)
	_ctx.bus().trade().trade_transaction_failed.connect(_on_transaction_failed)

	var inventory := _ctx.get_inventory()
	if is_instance_valid(inventory):
		inventory.inventory_changed.connect(func(pid: String, _items: Array) -> void: _on_inventory_changed(pid))

	var currency := _ctx.get_currency()
	if is_instance_valid(currency):
		currency.gold_changed.connect(func(pid: String, _amt: int, _d: int) -> void: _on_inventory_changed(pid))

# ─────────────────────────────────────────────
# Einladung
# ─────────────────────────────────────────────

func _on_invite_received(to_player_id: String, from_player_id: String) -> void:
	if to_player_id != _ctx.get_local_player_id():
		return
	_pending_invite_from = from_player_id
	_visuals.open_invite(_format_player_name(from_player_id))

func _on_invite_declined(player_id: String) -> void:
	if player_id != _ctx.get_local_player_id():
		return
	_pending_invite_from = ""
	_visuals.close_invite()
	_ctx.bus().ui().emit_notification_requested("Handelsanfrage abgelehnt.")

func _on_invite_accept() -> void:
	var trade := _ctx.get_trade_service()
	if is_instance_valid(trade):
		trade.request_respond_invite(_ctx.get_local_player_id(), true)
	_pending_invite_from = ""
	_visuals.close_invite()

func _on_invite_decline() -> void:
	var trade := _ctx.get_trade_service()
	if is_instance_valid(trade):
		trade.request_respond_invite(_ctx.get_local_player_id(), false)
	_pending_invite_from = ""
	_visuals.close_invite()

# ─────────────────────────────────────────────
# Session
# ─────────────────────────────────────────────

func _on_session_started(_session_id: String, player_a: String, player_b: String) -> void:
	var local_id := _ctx.get_local_player_id()
	if local_id != player_a and local_id != player_b:
		return
	_visuals.close_invite()
	var partner_id := player_b if local_id == player_a else player_a
	_visuals.open(_format_player_name(partner_id))
	_refresh()

func _on_session_updated(_session_id: String) -> void:
	if not _visuals.panel.visible:
		return
	_refresh()

func _on_session_cancelled(_session_id: String, reason: String) -> void:
	if not _visuals.panel.visible:
		return
	_visuals.close()
	_ctx.bus().ui().emit_notification_requested(_cancel_reason_text(reason))

func _on_trade_completed(_session_id: String, player_a: String, player_b: String) -> void:
	var local_id := _ctx.get_local_player_id()
	if local_id != player_a and local_id != player_b:
		return
	_visuals.close()
	_ctx.bus().ui().emit_notification_requested("Handel abgeschlossen!")

func _on_transaction_failed(player_id: String, _session_id: String, reason: String) -> void:
	if player_id != _ctx.get_local_player_id():
		return
	_ctx.bus().ui().emit_notification_requested(_failure_reason_text(reason))

func _on_inventory_changed(player_id: String) -> void:
	if player_id != _ctx.get_local_player_id() or not _visuals.panel.visible:
		return
	_refresh_inventory_list()
	_refresh_carried_gold()

func _refresh_carried_gold() -> void:
	var currency := _ctx.get_currency()
	if is_instance_valid(currency):
		_visuals.update_carried_gold(currency.get_gold(_ctx.get_local_player_id()))

# ─────────────────────────────────────────────
# Angebot bearbeiten — liest IMMER den aktuellen Session-Stand, siehe
# Klassenkommentar (kein lokaler Zustand).
# ─────────────────────────────────────────────

func _on_add_item(item_id: String) -> void:
	var session := _current_session()
	if session.is_empty():
		return
	var offer: Dictionary = _my_offer(session)
	var items: Dictionary = (offer["items"] as Dictionary).duplicate()
	items[item_id] = int(items.get(item_id, 0)) + 1
	_push_offer(session, items, int(offer["gold"]))

func _on_remove_item(item_id: String) -> void:
	var session := _current_session()
	if session.is_empty():
		return
	var offer: Dictionary = _my_offer(session)
	var items: Dictionary = (offer["items"] as Dictionary).duplicate()
	if not items.has(item_id):
		return
	var remaining: int = int(items[item_id]) - 1
	if remaining <= 0:
		items.erase(item_id)
	else:
		items[item_id] = remaining
	_push_offer(session, items, int(offer["gold"]))

func _on_set_gold(amount: int) -> void:
	var session := _current_session()
	if session.is_empty():
		return
	var offer: Dictionary = _my_offer(session)
	_push_offer(session, (offer["items"] as Dictionary).duplicate(), amount)

func _push_offer(session: Dictionary, items: Dictionary, gold: int) -> void:
	var trade := _ctx.get_trade_service()
	if is_instance_valid(trade):
		trade.request_update_offer(_ctx.get_local_player_id(), String(session["session_id"]), items, gold)

func _on_ready_toggled(ready: bool) -> void:
	var session := _current_session()
	if session.is_empty():
		return
	var trade := _ctx.get_trade_service()
	if is_instance_valid(trade):
		trade.request_set_ready(_ctx.get_local_player_id(), String(session["session_id"]), ready)

func _on_confirm_pressed() -> void:
	var session := _current_session()
	if session.is_empty():
		return
	var trade := _ctx.get_trade_service()
	if is_instance_valid(trade):
		trade.request_set_confirmed(_ctx.get_local_player_id(), String(session["session_id"]), true)

func _on_close_requested() -> void:
	var session := _current_session()
	if not session.is_empty():
		var trade := _ctx.get_trade_service()
		if is_instance_valid(trade):
			trade.request_cancel(_ctx.get_local_player_id(), String(session["session_id"]))
	_visuals.close()

# ─────────────────────────────────────────────
# Anzeige-Refresh
# ─────────────────────────────────────────────

func _refresh() -> void:
	var session := _current_session()
	if session.is_empty():
		return
	var is_a := String(session["player_a"]) == _ctx.get_local_player_id()
	var my_offer: Dictionary = session["offer_a"] if is_a else session["offer_b"]
	var their_offer: Dictionary = session["offer_b"] if is_a else session["offer_a"]
	var my_ready: bool = bool(session.get("ready_a" if is_a else "ready_b", false))
	var their_ready: bool = bool(session.get("ready_b" if is_a else "ready_a", false))

	_visuals.set_my_offer(_entries_for(my_offer), int(my_offer.get("gold", 0)), _on_remove_item)
	_visuals.set_their_offer(_entries_for(their_offer), int(their_offer.get("gold", 0)))
	_visuals.update_ready_state(my_ready, their_ready, my_ready and their_ready)
	_visuals.set_status(_status_text(my_ready, their_ready))
	_refresh_inventory_list()
	_refresh_carried_gold()

func _refresh_inventory_list() -> void:
	var inventory := _ctx.get_inventory()
	if not is_instance_valid(inventory):
		return
	var entries: Array[Dictionary] = []
	for stack in inventory.get_all_items(_ctx.get_local_player_id()):
		entries.append({"item_id": stack["id"], "display_name": stack["name"], "quantity": stack["quantity"]})
	_visuals.set_inventory_entries(entries, _on_add_item)

func _entries_for(offer: Dictionary) -> Array[Dictionary]:
	var data := _ctx.get_data()
	var out: Array[Dictionary] = []
	var items: Dictionary = offer.get("items", {})
	for item_id in items:
		var def: ItemDefinition = data.get_item(String(item_id)) if is_instance_valid(data) else null
		out.append({
			"item_id": item_id,
			"display_name": def.display_name if is_instance_valid(def) else String(item_id),
			"quantity": int(items[item_id]),
		})
	return out

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _current_session() -> Dictionary:
	var trade := _ctx.get_trade_service()
	if not is_instance_valid(trade):
		return {}
	return trade.get_session_for(_ctx.get_local_player_id())

func _my_offer(session: Dictionary) -> Dictionary:
	var is_a := String(session["player_a"]) == _ctx.get_local_player_id()
	return session["offer_a"] if is_a else session["offer_b"]

## player_id ist bei diesem Projekt der gewählte Charaktername (siehe
## MainMenuController._format_character_name()), keine UUID — dieselbe
## Formatierung wird hier für die Anzeige im Handels-Panel wiederverwendet.
func _format_player_name(player_id: String) -> String:
	return player_id.replace("_", " ").capitalize()

func _status_text(my_ready: bool, their_ready: bool) -> String:
	if my_ready and their_ready:
		return "Beide bereit — prüft das Angebot und bestätigt."
	if my_ready and not their_ready:
		return "Warte auf die Gegenseite..."
	return ""

func _cancel_reason_text(reason: String) -> String:
	match reason:
		"cancelled_by_player":
			return "Handel wurde abgebrochen."
		"offer_no_longer_valid":
			return "Handel abgebrochen: ein Angebot war nicht mehr gültig."
		_:
			return "Handel abgebrochen."

func _failure_reason_text(reason: String) -> String:
	match reason:
		"not_ready":
			return "Beide Seiten müssen erst bereit sein."
		"remove_failed":
			return "Handel fehlgeschlagen: Gegenstand konnte nicht entnommen werden."
		"recipient_cannot_receive":
			return "Handel fehlgeschlagen: Gegenseite kann das Angebot nicht annehmen."
		"invalid_gold_amount":
			return "Ungültiger Gold-Betrag."
		"invalid_item_quantity":
			return "Ungültige Anzahl."
		_:
			return "Vorgang fehlgeschlagen."
