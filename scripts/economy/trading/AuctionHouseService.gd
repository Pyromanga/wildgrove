extends Service
class_name AuctionHouseService
## implements ISaveProvider

## AuctionHouseService — ADR-035: asynchroner Marktplatz-Teil (Gegenstück zum
## synchronen Handshake in TradeService).
##
## QUELLEN-PRIORITÄT beim Listen (ADR-035-Entscheidung): existiert derselbe
## item_id-Bestand sowohl im Inventar als auch in der Bank, wird ZUERST aus
## dem Inventar entnommen, erst wenn das nicht reicht aus der Bank — siehe
## _resolve_listing_source().
##
## ESCROW: das gelistete Item wird SOFORT beim Listen aus seinem
## Ursprungsspeicher entzogen (Inventar ODER Bank, je nach Quelle) und lebt
## bis Kauf/Stornierung ausschließlich in _listings — anders als
## TradeService, das bewusst KEIN Escrow nutzt (siehe dortiger
## Klassenkommentar für die Begründung des Unterschieds). Eine Stornierung
## gibt das Item an genau die Quelle zurück, aus der es entnommen wurde
## (_listing.source), nicht pauschal ins Inventar.
##
## GOLD läuft NICHT über Escrow — der Käufer zahlt server-seitig validiertes
## Gold direkt über CurrencyService; das Gold landet beim Verkäufer auch wenn
## dieser offline ist (CurrencyService kennt keinen "online"-Begriff, reine
## player_id-verschachtelte Autoritäts-Daten).
##
## LIVE-BROADCAST (Round 97, ADR-042): jede Listing-Änderung (Listen, Kauf,
## Storno) sendet zusätzlich zur gezielten Bestätigung an den Akteur
## (`_send_to()`) einen vollen Listings-Snapshot per
## `NetworkBridge.broadcast_to_all_peers()` an ALLE aktuell verbundenen
## Spieler — nicht nur an den, der die Aktion ausgelöst hat. Wer den
## Marktplatz gerade offen hat, sieht neue/verschwundene Listings ohne
## manuelles Neu-Öffnen. Der bestehende Pull-Pfad (`request_listings_snapshot()`)
## bleibt zusätzlich bestehen — er ist weiterhin der richtige Weg für den
## initialen Snapshot beim allerersten Öffnen des Marktplatz-Panels (der
## Broadcast liefert nur *Änderungen*, keinen initialen Zustand für einen
## Client, der das Panel noch nie geöffnet hatte). Siehe ADR-042 „Verhältnis
## zu ADR-035" für die volle Begründung des Broadcast-vs-Pull-Zusammenspiels.

## ADR-050 Phase 2 (Round 113): `purchase_completed`/`transaction_failed`
## sind nach scripts/economy/trading/AuctionEvents.gd (EventBus-Namespace
## `auction`) migriert — der einzige externe Konsument (AuctionHouseUIController)
## holt sich diese Instanz per DI (`_ctx.get_auction_house()`), kein lokaler
## Node-Subtree-Connect blieb übrig, siehe AuctionEvents.gd-Klassenkommentar.
## `transaction_failed` hieß hier außerdem identisch wie auf BankService/
## TradeService/ShopService (ADR-050 Phase 1, Round 111 aufgelöst) — jetzt
## eindeutig `auction_transaction_failed`.
## `listing_created`/`listing_cancelled`/`listings_updated` bleiben bewusst
## native Signale — nicht Teil dieses Batches (kein Namenskollision-Fall).

signal listing_created(listing_id: String, seller_id: String)
signal listing_cancelled(listing_id: String)
signal listings_updated(listings: Array)

const LOG_CAT := "AuctionHouse"
const SAVE_KEY := "auction_house"
const SOURCE_INVENTORY := "inventory"
const SOURCE_BANK := "bank"

var _inventory: InventorySystem = null
var _currency:  CurrencyService = null
var _bank:      BankService     = null
var _data:      DataService     = null
var _network:   NetworkBridge   = null
var _save_system: SaveSystem    = null
var _bus:       IEventBus       = null

## listing_id -> { seller_id, item_id, quantity, price, source ("inventory"|"bank") }
var _listings: Dictionary = {}

# ─────────────────────────────────────────────
# Phase 4: Configure (DI)
# ─────────────────────────────────────────────

func configure(deps: ServiceDeps) -> void:
	_inventory   = deps.require(ServiceKeys.INVENTORY) as InventorySystem
	_currency    = deps.require(ServiceKeys.CURRENCY)  as CurrencyService
	_bank        = deps.require(ServiceKeys.BANK)      as BankService
	_data        = deps.require(ServiceKeys.DATA)      as DataService
	_network     = deps.get_optional(ServiceKeys.NETWORK_BRIDGE) as NetworkBridge
	_save_system = deps.get_optional(ServiceKeys.SAVE_SYSTEM)    as SaveSystem
	_bus         = deps.get_optional(ServiceKeys.EVENT_BUS)      as IEventBus
	_connect_economy_sync()

	if _save_system:
		_save_system.register_save_provider(self)
		var saved: Variant = _save_system.get_state_for(SAVE_KEY)
		if saved is Dictionary and not (saved as Dictionary).is_empty():
			_restore_from_save(saved)
	else:
		AppLogger.log_error("Abhängigkeit 'savesystem' fehlt!", LOG_CAT)

	AppLogger.log_info("AuctionHouseService initialisiert.", LOG_CAT)

func inject_network_bridge(network: NetworkBridge) -> void:
	_network = network
	_connect_economy_sync()

func _connect_economy_sync() -> void:
	if not is_instance_valid(_network):
		return
	if not _network.economy_state_received.is_connected(_on_economy_state_received):
		_network.economy_state_received.connect(_on_economy_state_received)
	# ADR-042 (Round 97): derselbe Payload-Umschlag (kind == "auction_house",
	# gleiches event/listings-Format) läuft jetzt auch über den generischen
	# Broadcast-Kanal ein — beide Signale haben identische Signatur
	# (kind: String, payload: Dictionary), daher reicht ein gemeinsamer
	# Handler statt einer zweiten, redundanten Dispatch-Funktion.
	if not _network.broadcast_event_received.is_connected(_on_economy_state_received):
		_network.broadcast_event_received.connect(_on_economy_state_received)

func on_cleanup() -> void:
	if not is_instance_valid(_network):
		return
	if _network.economy_state_received.is_connected(_on_economy_state_received):
		_network.economy_state_received.disconnect(_on_economy_state_received)
	if _network.broadcast_event_received.is_connected(_on_economy_state_received):
		_network.broadcast_event_received.disconnect(_on_economy_state_received)

# ─────────────────────────────────────────────
# Client-Empfang (R-7/ADR-022-Muster, kind == "auction_house") — bekommt
# sowohl gezielte 1:1-Antworten (economy_state_received, z. B. eigene
# transaction_failed) als auch die neuen Broadcast-Updates (ADR-042,
# broadcast_event_received, "listings_snapshot" bei fremden Aktionen).
# ─────────────────────────────────────────────

func _on_economy_state_received(kind: String, payload: Dictionary) -> void:
	if kind != "auction_house":
		return
	match String(payload.get("event", "")):
		"listings_snapshot":
			var listings: Array = payload.get("listings", [])
			listings_updated.emit(listings)
		"listing_created":
			listing_created.emit(String(payload.get("listing_id", "")), String(payload.get("seller_id", "")))
		"listing_cancelled":
			listing_cancelled.emit(String(payload.get("listing_id", "")))
		"purchase_completed":
			if is_instance_valid(_bus):
				_bus.auction().emit_auction_transaction_purchase_completed(
					String(payload.get("listing_id", "")), String(payload.get("buyer_id", "")),
					String(payload.get("seller_id", "")), String(payload.get("item_id", "")),
					int(payload.get("quantity", 0)), int(payload.get("price", 0))
				)
		"transaction_failed":
			if is_instance_valid(_bus):
				_bus.auction().emit_auction_transaction_failed(String(payload.get("player_id", "")), String(payload.get("reason", "")))

# ─────────────────────────────────────────────
# Öffentliche API — Abfrage (nur auf der Autorität sinnvoll vollständig;
# siehe request_listings_snapshot() für den Client-Pfad)
# ─────────────────────────────────────────────

func get_all_listings() -> Array:
	var out: Array[Dictionary] = []
	for lid in _listings:
		var l: Dictionary = _listings[lid]
		var def: ItemDefinition = _data.get_item(String(l["item_id"])) if is_instance_valid(_data) else null
		out.append({
			"listing_id": lid,
			"seller_id":  l["seller_id"],
			"item_id":    l["item_id"],
			"item_name":  def.display_name if is_instance_valid(def) else l["item_id"],
			"quantity":   l["quantity"],
			"price":      l["price"],
		})
	return out

func get_listings_by_seller(player_id: String) -> Array:
	return get_all_listings().filter(func(l: Dictionary) -> bool: return l["seller_id"] == player_id)

func request_listings_snapshot(player_id: String) -> void:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		_network.send_auction_request_snapshot(player_id)
	else:
		_send_to(player_id, {"event": "listings_snapshot", "listings": get_all_listings()})

# ─────────────────────────────────────────────
# Listen
# ─────────────────────────────────────────────

func request_list_item(player_id: String, item_id: String, quantity: int, price: int) -> void:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		_network.send_auction_list_item(item_id, quantity, price, player_id)
	else:
		on_list_item_confirmed(player_id, item_id, quantity, price)

func on_list_item_confirmed(player_id: String, item_id: String, quantity: int, price: int) -> void:
	if not _require_authority("on_list_item_confirmed"):
		return
	if quantity <= 0 or price <= 0:
		_fail(player_id, "invalid_listing_parameters")
		return
	if not is_instance_valid(_data) or not is_instance_valid(_data.get_item(item_id)):
		_fail(player_id, "unknown_item")
		return

	var source := _resolve_listing_source(player_id, item_id, quantity)
	if source.is_empty():
		_fail(player_id, "item_not_owned")
		return

	var removed := false
	if source == SOURCE_INVENTORY:
		removed = _inventory.remove_item(item_id, player_id, quantity)
	else:
		removed = _bank.remove_item_for_listing(player_id, item_id, quantity)
	if not removed:
		_fail(player_id, "item_not_owned")
		return

	var listing_id := UuidGen.generate_v4()
	_listings[listing_id] = {
		"seller_id": player_id,
		"item_id":   item_id,
		"quantity":  quantity,
		"price":     price,
		"source":    source,
	}
	listing_created.emit(listing_id, player_id)
	_send_to(player_id, {"event": "listing_created", "listing_id": listing_id, "seller_id": player_id})
	_broadcast_listings_update()
	AppLogger.log_debug(
		"Neues Listing '%s': '%s' bietet %dx '%s' für %d Gold (Quelle: %s)."
		% [listing_id, player_id, quantity, item_id, price, source],
		LOG_CAT
	)

## Quellen-Priorität aus ADR-035: zuerst Inventar, erst wenn das nicht reicht Bank.
func _resolve_listing_source(player_id: String, item_id: String, quantity: int) -> String:
	if is_instance_valid(_inventory) and _inventory.has_item(item_id, player_id, quantity):
		return SOURCE_INVENTORY
	# BankService hat kein has_item() (siehe dortige API) — direkt über die
	# rohe ItemInstance prüfen, analog get_bank_item_instance().
	var inst: ItemInstance = _bank.get_bank_item_instance(player_id, item_id) if is_instance_valid(_bank) else null
	if is_instance_valid(inst) and inst.quantity >= quantity:
		return SOURCE_BANK
	return ""

# ─────────────────────────────────────────────
# Kaufen
# ─────────────────────────────────────────────

func request_buy_item(buyer_id: String, listing_id: String) -> void:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		_network.send_auction_buy_item(listing_id, buyer_id)
	else:
		on_buy_confirmed(buyer_id, listing_id)

func on_buy_confirmed(buyer_id: String, listing_id: String) -> void:
	if not _require_authority("on_buy_confirmed"):
		return
	var listing: Dictionary = _listings.get(listing_id, {})
	if listing.is_empty():
		_fail(buyer_id, "listing_not_found")
		return
	var seller_id: String = String(listing["seller_id"])
	if seller_id == buyer_id:
		_fail(buyer_id, "cannot_buy_own_listing")
		return
	var price: int = int(listing["price"])
	if not _currency.has_gold(buyer_id, price):
		_fail(buyer_id, "insufficient_gold")
		return
	if not _currency.request_remove_gold(buyer_id, price):
		_fail(buyer_id, "insufficient_gold")
		return

	var item_id: String = String(listing["item_id"])
	var quantity: int = int(listing["quantity"])
	if not _inventory.request_add_item(item_id, buyer_id, quantity):
		_currency.request_add_gold(buyer_id, price)  # Rollback, analog BankService.on_withdraw_gold_confirmed()
		_fail(buyer_id, "inventory_full")
		return

	# Escrow-Modell: Gold geht an den Verkäufer auch wenn offline — CurrencyService
	# ist reine player_id-verschachtelte Autoritätsdaten, kein "online"-Erfordernis.
	_currency.request_add_gold(seller_id, price)
	_listings.erase(listing_id)

	if is_instance_valid(_bus):
		_bus.auction().emit_auction_transaction_purchase_completed(listing_id, buyer_id, seller_id, item_id, quantity, price)
	_send_to(buyer_id, {
		"event": "purchase_completed", "listing_id": listing_id, "buyer_id": buyer_id,
		"seller_id": seller_id, "item_id": item_id, "quantity": quantity, "price": price,
	})
	_broadcast_listings_update()
	AppLogger.log_info(
		"Verkauft: '%s' kauft %dx '%s' von '%s' für %d Gold (Listing %s)."
		% [buyer_id, quantity, item_id, seller_id, price, listing_id],
		LOG_CAT
	)

# ─────────────────────────────────────────────
# Stornieren
# ─────────────────────────────────────────────

func request_cancel_listing(player_id: String, listing_id: String) -> void:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		_network.send_auction_cancel_listing(listing_id, player_id)
	else:
		on_cancel_listing_confirmed(player_id, listing_id)

func on_cancel_listing_confirmed(player_id: String, listing_id: String) -> void:
	if not _require_authority("on_cancel_listing_confirmed"):
		return
	var listing: Dictionary = _listings.get(listing_id, {})
	if listing.is_empty() or String(listing["seller_id"]) != player_id:
		_fail(player_id, "listing_not_found")
		return

	var item_id: String = String(listing["item_id"])
	var quantity: int = int(listing["quantity"])
	var returned := false
	if String(listing["source"]) == SOURCE_INVENTORY:
		returned = _inventory.request_add_item(item_id, player_id, quantity)
	else:
		var def: ItemDefinition = _data.get_item(item_id) if is_instance_valid(_data) else null
		if is_instance_valid(def):
			_bank.add_item_to_bank(player_id, item_id, quantity, def)
			returned = true
	if not returned:
		_fail(player_id, "return_failed")
		return

	_listings.erase(listing_id)
	listing_cancelled.emit(listing_id)
	_send_to(player_id, {"event": "listing_cancelled", "listing_id": listing_id})
	_broadcast_listings_update()

# ─────────────────────────────────────────────
# Save-Interface
# ─────────────────────────────────────────────

func get_save_key() -> String:
	return SAVE_KEY

func get_save_data() -> Dictionary:
	return {"listings": _listings.duplicate(true)}

func _restore_from_save(saved: Dictionary) -> void:
	if saved.get("listings") is Dictionary:
		_listings = (saved["listings"] as Dictionary).duplicate(true)

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _fail(player_id: String, reason: String) -> void:
	if is_instance_valid(_bus):
		_bus.auction().emit_auction_transaction_failed(player_id, reason)
	_send_to(player_id, {"event": "transaction_failed", "player_id": player_id, "reason": reason})

func _send_to(player_id: String, payload: Dictionary) -> void:
	if is_instance_valid(_network):
		_network.send_economy_update_for_player(player_id, "auction_house", payload)

## ADR-042 (Round 97): informiert ALLE aktuell verbundenen Spieler über den
## neuen Listings-Stand — nicht nur den Akteur der gerade laufenden Aktion
## (dafür bleibt _send_to() zuständig, inkl. Fehlerfälle, die niemand sonst
## etwas angehen). Bewusst ein voller Snapshot statt eines Patches, exakt das
## Format, das request_listings_snapshot() ohnehin schon liefert (kind ==
## "auction_house", event == "listings_snapshot") — Empfänger-Client braucht
## dafür keinen zweiten Merge-Pfad, _on_economy_state_received() verarbeitet
## beide Quellen identisch.
func _broadcast_listings_update() -> void:
	if is_instance_valid(_network):
		_network.broadcast_to_all_peers("auction_house", {"event": "listings_snapshot", "listings": get_all_listings()})

func _require_authority(caller: String) -> bool:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		AppLogger.log_error("%s: Aufruf auf Nicht-Autorität — verweigert." % caller, LOG_CAT)
		return false
	return true
