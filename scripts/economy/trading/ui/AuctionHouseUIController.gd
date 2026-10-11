class_name AuctionHouseUIController
extends Node

## AuctionHouseUIController — öffnet/befüllt das Auktionshaus-Panel, leitet
## Listen-/Kauf-/Storno-Klicks an AuctionHouseService weiter. Analog
## BankUIController/ShopUIController: öffnet über den NPC-"opened"-Umweg
## (auction_house_opened), anders als TradeUIController, das direkt auf
## TradeService lauscht (siehe UIEvents.gd-Klassenkommentar für die
## Begründung des Unterschieds).
##
## LISTEN-QUELLE: ADR-035 erlaubt Listen aus Inventar ODER Bank, Priorität
## Inventar zuerst — diese Entscheidung trifft AuctionHouseService selbst
## (_resolve_listing_source()), NICHT die UI. Der Controller zeigt daher pro
## Item die KOMBINIERTE verfügbare Menge (Inventar + Bank) und schickt beim
## Listen nur item_id/quantity/price — welche Quelle tatsächlich entnommen
## wird, entscheidet die Autorität.

var _visuals: AuctionHouseVisuals
var _ctx: IUIContext

func setup(visuals: AuctionHouseVisuals, ctx: IUIContext) -> void:
	_visuals = visuals
	_ctx     = ctx

	_visuals.close_requested.connect(_on_close_requested)
	_visuals.buy_requested.connect(_on_buy_requested)
	_visuals.cancel_requested.connect(_on_cancel_requested)
	_visuals.list_requested.connect(_on_list_requested)

	_ctx.bus().ui().auction_house_opened.connect(_on_opened)
	_ctx.bus().ui().auction_house_closed.connect(_on_close_requested)

	var auction := _ctx.get_auction_house()
	if is_instance_valid(auction):
		auction.listings_updated.connect(_on_listings_updated)
		auction.listing_created.connect(func(_lid: String, _sid: String) -> void: _request_snapshot())
		auction.listing_cancelled.connect(func(_lid: String) -> void: _request_snapshot())
	_ctx.bus().auction().auction_transaction_purchase_completed.connect(_on_purchase_completed)
	_ctx.bus().auction().auction_transaction_failed.connect(_on_transaction_failed)

	var currency := _ctx.get_currency()
	if is_instance_valid(currency):
		currency.gold_changed.connect(func(pid: String, _amt: int, _d: int) -> void: _on_state_changed(pid))

	var inventory := _ctx.get_inventory()
	if is_instance_valid(inventory):
		inventory.inventory_changed.connect(func(pid: String, _items: Array) -> void: _on_state_changed(pid))

	var bank := _ctx.get_bank()
	# ADR-050 Phase 2 (Round 112): deposit_completed/withdraw_completed sind
	# von nativen BankService-Signalen nach EventBus.bank() (Path B,
	# ADR-012) migriert — `bank` bleibt für get_bank_items() unten gebraucht.
	# Round 113: auf bank_transaction_deposit_completed/
	# bank_transaction_withdrawal_completed umbenannt (Namensschema-
	# Vereinheitlichung, siehe BankEvents.gd).
	_ctx.bus().bank().bank_transaction_deposit_completed.connect(func(pid: String, _k: String, _id: String, _amt: int) -> void: _on_state_changed(pid))
	_ctx.bus().bank().bank_transaction_withdrawal_completed.connect(func(pid: String, _k: String, _id: String, _amt: int) -> void: _on_state_changed(pid))

func _on_opened(npc_display_name: String) -> void:
	_visuals.open(npc_display_name)
	_refresh_carried_gold()
	_refresh_inventory_list()
	_request_snapshot()

func _on_close_requested() -> void:
	_visuals.close()

func _on_state_changed(player_id: String) -> void:
	if not _visuals.panel.visible or player_id != _ctx.get_local_player_id():
		return
	_refresh_carried_gold()
	_refresh_inventory_list()

func _request_snapshot() -> void:
	var auction := _ctx.get_auction_house()
	if is_instance_valid(auction):
		auction.request_listings_snapshot(_ctx.get_local_player_id())

func _on_listings_updated(listings: Array) -> void:
	if not _visuals.panel.visible:
		return
	_render_listings(listings)

func _on_purchase_completed(_listing_id: String, buyer_id: String, seller_id: String, item_id: String, quantity: int, price: int) -> void:
	var local_id := _ctx.get_local_player_id()
	if local_id != buyer_id and local_id != seller_id:
		return
	if not _visuals.panel.visible:
		return
	var display_name := _display_name_for(item_id)
	if local_id == buyer_id:
		_ctx.bus().ui().emit_notification_requested("Gekauft: %dx %s für %d Gold." % [quantity, display_name, price])
	else:
		_ctx.bus().ui().emit_notification_requested("Verkauft: %dx %s für %d Gold." % [quantity, display_name, price])
	_request_snapshot()

func _on_transaction_failed(player_id: String, reason: String) -> void:
	if player_id != _ctx.get_local_player_id():
		return
	_ctx.bus().ui().emit_notification_requested(_reason_text(reason))

func _display_name_for(item_id: String) -> String:
	var data := _ctx.get_data()
	if not is_instance_valid(data):
		return item_id
	var def: ItemDefinition = data.get_item(item_id)
	return def.display_name if is_instance_valid(def) else item_id

func _reason_text(reason: String) -> String:
	match reason:
		"invalid_listing_parameters":
			return "Ungültige Menge oder Preis."
		"unknown_item":
			return "Unbekannter Gegenstand."
		"item_not_owned":
			return "Das hast du nicht (mehr) in der Menge."
		"listing_not_found":
			return "Angebot nicht mehr verfügbar."
		"cannot_buy_own_listing":
			return "Du kannst dein eigenes Angebot nicht kaufen."
		"insufficient_gold":
			return "Nicht genug Gold."
		"inventory_full":
			return "Inventar voll."
		"return_failed":
			return "Rückgabe fehlgeschlagen."
		_:
			return "Vorgang fehlgeschlagen."

# ─────────────────────────────────────────────
# Aktionen
# ─────────────────────────────────────────────

func _on_buy_requested(listing_id: String) -> void:
	var auction := _ctx.get_auction_house()
	if is_instance_valid(auction):
		auction.request_buy_item(_ctx.get_local_player_id(), listing_id)

func _on_cancel_requested(listing_id: String) -> void:
	var auction := _ctx.get_auction_house()
	if is_instance_valid(auction):
		auction.request_cancel_listing(_ctx.get_local_player_id(), listing_id)

func _on_list_requested(item_id: String, quantity: int, price: int) -> void:
	var auction := _ctx.get_auction_house()
	if is_instance_valid(auction):
		auction.request_list_item(_ctx.get_local_player_id(), item_id, quantity, price)

# ─────────────────────────────────────────────
# Anzeige-Refresh
# ─────────────────────────────────────────────

func _render_listings(listings: Array) -> void:
	var local_id := _ctx.get_local_player_id()
	var entries: Array[Dictionary] = []
	for l in listings:
		var listing: Dictionary = l
		entries.append({
			"listing_id": listing["listing_id"],
			"item_name":  listing["item_name"],
			"quantity":   listing["quantity"],
			"price":      listing["price"],
			"seller_id":  listing["seller_id"],
			"is_own":     String(listing["seller_id"]) == local_id,
		})
	_visuals.set_listings(entries)

func _refresh_carried_gold() -> void:
	var currency := _ctx.get_currency()
	if is_instance_valid(currency):
		_visuals.update_carried_gold(currency.get_gold(_ctx.get_local_player_id()))

## Kombiniert Inventar- und Bank-Bestand pro item_id (ADR-035: beide Quellen
## sind listbar, siehe Klassenkommentar) — reine Anzeige, die tatsächliche
## Quellwahl trifft die Autorität beim Listen selbst.
func _refresh_inventory_list() -> void:
	var inventory := _ctx.get_inventory()
	var bank := _ctx.get_bank()
	var local_id := _ctx.get_local_player_id()
	var combined: Dictionary = {}  # item_id -> {display_name, quantity}

	if is_instance_valid(inventory):
		for stack in inventory.get_all_items(local_id):
			_accumulate(combined, stack["id"], stack["name"], int(stack["quantity"]))
	if is_instance_valid(bank):
		for stack in bank.get_bank_items(local_id):
			_accumulate(combined, stack["id"], stack["name"], int(stack["quantity"]))

	var entries: Array[Dictionary] = []
	for item_id in combined:
		var e: Dictionary = combined[item_id]
		entries.append({"item_id": item_id, "display_name": e["display_name"], "quantity": e["quantity"]})
	_visuals.set_inventory_entries(entries)

func _accumulate(combined: Dictionary, item_id: String, display_name: String, quantity: int) -> void:
	if combined.has(item_id):
		combined[item_id]["quantity"] += quantity
	else:
		combined[item_id] = {"display_name": display_name, "quantity": quantity}
