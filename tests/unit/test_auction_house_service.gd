# res://tests/unit/test_auction_house_service.gd
extends GutTest

## Unit-Tests für AuctionHouseService (ADR-035, asynchroner Marktplatz-Teil).
##
## Strategie: InventorySystem, CurrencyService und BankService werden ECHT
## instanziiert (gleiches Muster wie test_bank_service.gd/test_trade_service.
## gd) — die Quellen-Priorität Inventar-vor-Bank und das Escrow-Verhalten
## sind genau das, was hier getestet werden soll, und sollen gegen den
## echten Bestand beider Kollaboratoren laufen statt gegen einen Stub, der
## das wegabstrahiert. DataService ebenfalls über einen minimalen Mock mit
## echten ItemDefinition-Resourcen (analog test_bank_service.gd). Ein echter
## SaveSystem wird konfiguriert (billig, kein Mock nötig) — vermeidet die
## sonst bei jedem Test wiederholte "Abhängigkeit 'savesystem' fehlt!"-
## log_error()-Meldung (die GUT als Unexpected Error zählt und den Test
## fehlschlagen lässt). save_round_trip wird trotzdem separat direkt über
## get_save_data()/_restore_from_save() getestet, unabhängig vom echten
## SaveSystem, analog test_bank_service.gd. Kein NetworkBridge konfiguriert
## -> alle request_*() nehmen den synchronen else-Zweig direkt zu
## on_*_confirmed() (Tier-1-Pfad).
##
## Abgedeckt:
##   - Listen: Erfolg aus Inventar, Erfolg aus Bank wenn Inventar nicht
##     reicht (Quellen-Priorität ADR-035), ungültige Parameter, unbekanntes
##     Item, weder Inventar noch Bank reichen aus
##   - Kaufen: Erfolgsfall (Gold-Fluss + Item-Übergabe + Listing entfernt),
##     Listing nicht gefunden, eigenes Listing, zu wenig Gold,
##     Inventar voll -> Gold-Rollback
##   - Stornieren: Rückgabe an die ursprüngliche Quelle (Inventar/Bank),
##     falscher Verkäufer -> listing_not_found
##   - get_all_listings()/get_listings_by_seller() Formfragen
##   - Save-Round-Trip

class MockItemDef extends ItemDefinition:
	func _init(p_id: String, p_name: String, p_max_stack: int = 99) -> void:
		id            = p_id
		display_name  = p_name
		max_stack     = p_max_stack

class MockDataService extends DataService:
	func get_all_items() -> Dictionary:
		return _items

## Simuliert ein volles Inventar (request_add_item() schlägt immer fehl),
## um den Gold-Rollback-Pfad in on_buy_confirmed() zu erreichen, ohne
## InventorySystem selbst per echtem Gewichtslimit an seine Grenzen zu bringen.
class BlockedInventorySystem extends InventorySystem:
	func request_add_item(_item_id: String, _player_id: String, _quantity: int = 1) -> bool:
		return false

const ITEM_A := "iron_ore"
const SELLER := "seller-1"
const BUYER := "buyer-1"

var _svc: AuctionHouseService
var _inventory: InventorySystem
var _currency: CurrencyService
var _bank: BankService
var _ds: MockDataService
var _bus: MockEventBus
var _save: SaveSystem


func before_each() -> void:
	_ds = MockDataService.new()
	_ds._items[ITEM_A] = MockItemDef.new(ITEM_A, "Iron Ore", 50)
	_bus = MockEventBus.new()
	_save = SaveSystem.new()
	_save.configure(ServiceDeps.from_dict({ServiceKeys.EVENT_BUS: _bus}))

	_inventory = InventorySystem.new()
	_inventory.configure(ServiceDeps.from_dict({
		ServiceKeys.DATA:      _ds,
		ServiceKeys.SAVE_SYSTEM: _save,
		ServiceKeys.EVENT_BUS: _bus,
	}))

	_currency = CurrencyService.new()
	_currency.configure(ServiceDeps.from_dict({
		ServiceKeys.SAVE_SYSTEM: _save,
		ServiceKeys.EVENT_BUS: _bus,
	}))

	_bank = BankService.new()
	_bank.configure(ServiceDeps.from_dict({
		ServiceKeys.INVENTORY: _inventory,
		ServiceKeys.CURRENCY:  _currency,
		ServiceKeys.DATA:      _ds,
		ServiceKeys.SAVE_SYSTEM: _save,
	}))

	_svc = AuctionHouseService.new()
	_svc.configure(ServiceDeps.from_dict({
		ServiceKeys.INVENTORY: _inventory,
		ServiceKeys.CURRENCY:  _currency,
		ServiceKeys.BANK:      _bank,
		ServiceKeys.DATA:      _ds,
		ServiceKeys.SAVE_SYSTEM: _save,
		ServiceKeys.EVENT_BUS: _bus,
	}))


func after_each() -> void:
	_inventory.on_cleanup()
	_currency.on_cleanup()
	_svc = null
	_inventory = null
	_currency = null
	_bank = null
	_ds = null
	_bus = null


# ─────────────────────────────────────────────
# Listen — Quellen-Priorität und Validierung
# ─────────────────────────────────────────────

func test_list_item_from_inventory_removes_from_inventory() -> void:
	_inventory.on_item_add_confirmed(ITEM_A, 5, SELLER)
	var created: Array = []
	_svc.listing_created.connect(func(lid, sid): created.append(sid))
	_svc.request_list_item(SELLER, ITEM_A, 5, 100)
	assert_eq(created, [SELLER])
	assert_false(_inventory.has_item(ITEM_A, SELLER, 1), "Item muss aus dem Inventar entfernt sein (Escrow).")
	assert_eq(_svc.get_all_listings().size(), 1)

func test_list_item_prefers_inventory_over_bank_when_both_have_enough() -> void:
	_inventory.on_item_add_confirmed(ITEM_A, 5, SELLER)
	_bank.on_deposit_item_confirmed(ITEM_A, 5, SELLER)
	# jetzt: 0 im Inventar (gerade eingezahlt) -> erneut auffüllen, damit BEIDE Quellen reichen
	_inventory.on_item_add_confirmed(ITEM_A, 5, SELLER)
	_svc.request_list_item(SELLER, ITEM_A, 5, 100)
	assert_false(_inventory.has_item(ITEM_A, SELLER, 1), "Inventar-Bestand muss zuerst verbraucht werden.")
	assert_eq(_bank.get_bank_items(SELLER)[0]["quantity"], 5, "Bank-Bestand darf unangetastet bleiben, wenn Inventar reicht.")

func test_list_item_falls_back_to_bank_when_inventory_insufficient() -> void:
	_inventory.on_item_add_confirmed(ITEM_A, 2, SELLER)
	_bank.on_deposit_item_confirmed(ITEM_A, 2, SELLER)  # verschiebt die 2x ins Bank-Konto -> Inventar jetzt 0
	# Zustand: Inventar 0, Bank 2 -> Listing von 2 muss aus der Bank kommen.
	_svc.request_list_item(SELLER, ITEM_A, 2, 50)
	assert_true(_bank.get_bank_items(SELLER).is_empty(), "Bank-Bestand muss entnommen worden sein.")
	assert_eq(_svc.get_all_listings().size(), 1)

func test_list_item_rejects_non_positive_quantity_or_price() -> void:
	_inventory.on_item_add_confirmed(ITEM_A, 5, SELLER)
	var failed: Array = []
	_bus.auction().auction_transaction_failed.connect(func(pid, reason): failed.append(reason))
	_svc.request_list_item(SELLER, ITEM_A, 0, 100)
	_svc.request_list_item(SELLER, ITEM_A, 5, 0)
	assert_eq(failed, ["invalid_listing_parameters", "invalid_listing_parameters"])
	assert_true(_svc.get_all_listings().is_empty())

func test_list_item_rejects_unknown_item() -> void:
	var failed: Array = []
	_bus.auction().auction_transaction_failed.connect(func(pid, reason): failed.append(reason))
	_svc.request_list_item(SELLER, "does_not_exist", 1, 10)
	assert_eq(failed, ["unknown_item"])

func test_list_item_fails_when_neither_inventory_nor_bank_has_enough() -> void:
	_inventory.on_item_add_confirmed(ITEM_A, 1, SELLER)
	var failed: Array = []
	_bus.auction().auction_transaction_failed.connect(func(pid, reason): failed.append(reason))
	_svc.request_list_item(SELLER, ITEM_A, 5, 100)
	assert_eq(failed, ["item_not_owned"])
	assert_true(_inventory.has_item(ITEM_A, SELLER, 1), "Bei Fehlschlag darf das vorhandene 1x nicht angetastet werden.")


# ─────────────────────────────────────────────
# Kaufen
# ─────────────────────────────────────────────

func _make_listing(quantity: int = 5, price: int = 100) -> String:
	_inventory.on_item_add_confirmed(ITEM_A, quantity, SELLER)
	var created: Array = []
	_svc.listing_created.connect(func(lid, sid): created.append(lid))
	_svc.request_list_item(SELLER, ITEM_A, quantity, price)
	return String(created[0])

func test_buy_success_transfers_gold_and_item_and_removes_listing() -> void:
	var lid := _make_listing(5, 100)
	_currency.request_add_gold(BUYER, 150)

	var completed: Array = []
	_bus.auction().auction_transaction_purchase_completed.connect(func(l, b, s, item_id, qty, price): completed.append([l, b, s, item_id, qty, price]))
	_svc.request_buy_item(BUYER, lid)

	assert_eq(completed, [[lid, BUYER, SELLER, ITEM_A, 5, 100]])
	assert_eq(_currency.get_gold(BUYER), 50, "150 - 100 = 50.")
	assert_eq(_currency.get_gold(SELLER), 100, "Verkäufer erhält den vollen Preis.")
	assert_true(_inventory.has_item(ITEM_A, BUYER, 5))
	assert_true(_svc.get_all_listings().is_empty(), "Listing muss nach Kauf verschwunden sein.")

func test_buy_unknown_listing_fails() -> void:
	var failed: Array = []
	_bus.auction().auction_transaction_failed.connect(func(pid, reason): failed.append(reason))
	_svc.request_buy_item(BUYER, "no-such-listing")
	assert_eq(failed, ["listing_not_found"])

func test_buy_own_listing_fails() -> void:
	var lid := _make_listing(5, 100)
	_currency.request_add_gold(SELLER, 200)
	var failed: Array = []
	_bus.auction().auction_transaction_failed.connect(func(pid, reason): failed.append(reason))
	_svc.request_buy_item(SELLER, lid)
	assert_eq(failed, ["cannot_buy_own_listing"])

func test_buy_insufficient_gold_fails_without_side_effects() -> void:
	var lid := _make_listing(5, 100)
	_currency.request_add_gold(BUYER, 10)
	var failed: Array = []
	_bus.auction().auction_transaction_failed.connect(func(pid, reason): failed.append(reason))
	_svc.request_buy_item(BUYER, lid)
	assert_eq(failed, ["insufficient_gold"])
	assert_eq(_currency.get_gold(BUYER), 10)
	assert_false(_inventory.has_item(ITEM_A, BUYER, 1))
	assert_eq(_svc.get_all_listings().size(), 1, "Listing muss bei fehlgeschlagenem Kauf bestehen bleiben.")

func test_buy_inventory_full_rolls_back_gold() -> void:
	var lid := _make_listing(5, 100)
	_currency.request_add_gold(BUYER, 150)
	# Inventar des Käufers künstlich "voll" machen: max_stack von iron_ore auf
	# 0 wäre invasiv; stattdessen mocken wir InventorySystem nicht, sondern
	# nutzen den bereits vorhandenen realistischen Fehlerpfad über eine
	# eigene, absichtlich blockierende Sub-Klasse.
	var blocked := BlockedInventorySystem.new()
	blocked.configure(ServiceDeps.from_dict({
		ServiceKeys.DATA:      _ds,
		ServiceKeys.EVENT_BUS: _bus,
	}))
	_svc._inventory = blocked

	var failed: Array = []
	_bus.auction().auction_transaction_failed.connect(func(pid, reason): failed.append(reason))
	_svc.request_buy_item(BUYER, lid)
	assert_eq(failed, ["inventory_full"])
	assert_eq(_currency.get_gold(BUYER), 150, "Gold muss nach fehlgeschlagenem Inventar-Add vollständig zurückerstattet werden.")


# ─────────────────────────────────────────────
# Stornieren
# ─────────────────────────────────────────────

func test_cancel_listing_from_inventory_source_returns_to_inventory() -> void:
	var lid := _make_listing(5, 100)
	var cancelled: Array = []
	_svc.listing_cancelled.connect(func(l): cancelled.append(l))
	_svc.request_cancel_listing(SELLER, lid)
	assert_eq(cancelled, [lid])
	assert_true(_inventory.has_item(ITEM_A, SELLER, 5), "Storno muss an die ursprüngliche Quelle (Inventar) zurückgeben.")
	assert_true(_svc.get_all_listings().is_empty())

func test_cancel_listing_from_bank_source_returns_to_bank() -> void:
	_inventory.on_item_add_confirmed(ITEM_A, 2, SELLER)
	_bank.on_deposit_item_confirmed(ITEM_A, 2, SELLER)
	# Inventar jetzt 0 -> Listing muss aus der Bank kommen.
	var created: Array = []
	_svc.listing_created.connect(func(lid, sid): created.append(lid))
	_svc.request_list_item(SELLER, ITEM_A, 2, 50)
	var lid := String(created[0])

	_svc.request_cancel_listing(SELLER, lid)
	assert_eq(_bank.get_bank_items(SELLER)[0]["quantity"], 2, "Storno muss an die ursprüngliche Quelle (Bank) zurückgeben.")
	assert_false(_inventory.has_item(ITEM_A, SELLER, 1), "Inventar darf durch ein Bank-Quellen-Storno nicht befüllt werden.")

func test_cancel_listing_wrong_seller_fails() -> void:
	var lid := _make_listing(5, 100)
	var failed: Array = []
	_bus.auction().auction_transaction_failed.connect(func(pid, reason): failed.append(reason))
	_svc.request_cancel_listing(BUYER, lid)
	assert_eq(failed, ["listing_not_found"])
	assert_eq(_svc.get_all_listings().size(), 1, "Listing darf durch falschen Aufrufer nicht storniert werden.")

func test_cancel_unknown_listing_fails() -> void:
	var failed: Array = []
	_bus.auction().auction_transaction_failed.connect(func(pid, reason): failed.append(reason))
	_svc.request_cancel_listing(SELLER, "no-such-listing")
	assert_eq(failed, ["listing_not_found"])


# ─────────────────────────────────────────────
# Abfrage-API
# ─────────────────────────────────────────────

func test_get_all_listings_includes_item_name_from_data_service() -> void:
	var lid := _make_listing(3, 30)
	var listings := _svc.get_all_listings()
	assert_eq(listings.size(), 1)
	assert_eq(listings[0]["listing_id"], lid)
	assert_eq(listings[0]["item_name"], "Iron Ore")
	assert_eq(listings[0]["quantity"], 3)
	assert_eq(listings[0]["price"], 30)

func test_get_listings_by_seller_filters_correctly() -> void:
	_make_listing(1, 10)
	_inventory.on_item_add_confirmed(ITEM_A, 1, "other-seller")
	_svc.request_list_item("other-seller", ITEM_A, 1, 10)
	assert_eq(_svc.get_all_listings().size(), 2)
	assert_eq(_svc.get_listings_by_seller(SELLER).size(), 1)
	assert_eq(_svc.get_listings_by_seller("other-seller").size(), 1)


# ─────────────────────────────────────────────
# Save-Round-Trip
# ─────────────────────────────────────────────

func test_save_round_trip_preserves_listings() -> void:
	var lid := _make_listing(4, 40)
	var snapshot := _svc.get_save_data()

	var svc2 := AuctionHouseService.new()
	svc2._data = _ds
	svc2._restore_from_save(snapshot)

	assert_eq(svc2.get_all_listings().size(), 1)
	assert_eq(svc2.get_all_listings()[0]["listing_id"], lid)
	assert_eq(svc2.get_all_listings()[0]["quantity"], 4)

func test_save_data_key_is_auction_house() -> void:
	assert_eq(_svc.get_save_key(), "auction_house")


# ─────────────────────────────────────────────
# ADR-042 (Round 97): Live-Broadcast an alle Peers bei Listing-Änderungen
# ─────────────────────────────────────────────

class SpyNetworkBridge extends NetworkBridge:
	var broadcast_calls: Array[Dictionary] = []
	var send_calls: Array[Dictionary] = []
	func broadcast_to_all_peers(kind: String, payload: Dictionary) -> void:
		broadcast_calls.append({"kind": kind, "payload": payload})
	func send_economy_update_for_player(player_id: String, kind: String, payload: Dictionary) -> void:
		send_calls.append({"player_id": player_id, "kind": kind, "payload": payload})

## Für den Client-Routing-Zweig von request_listings_snapshot(): has_peer()/
## is_server() müssen hier echt überschrieben werden (SpyNetworkBridge oben
## hat einen echten NetworkBridge-Default, der ohne Multiplayer-Peer immer
## is_server()==true liefert, siehe NetworkBridge.gd).
class SnapshotClientSpyBridge extends NetworkBridge:
	var snapshot_request_calls: Array = []
	func has_peer() -> bool:
		return true
	func is_server() -> bool:
		return false
	func send_auction_request_snapshot(player_id: String) -> void:
		snapshot_request_calls.append(player_id)

func test_list_item_broadcasts_listings_snapshot_to_all_peers() -> void:
	var net := SpyNetworkBridge.new()
	add_child_autofree(net)
	_svc.inject_network_bridge(net)

	_inventory.on_item_add_confirmed(ITEM_A, 5, SELLER)
	_svc.request_list_item(SELLER, ITEM_A, 5, 100)

	assert_eq(net.broadcast_calls.size(), 1,
		"Listen muss genau einen Broadcast an alle Peers auslösen.")
	assert_eq(net.broadcast_calls[0]["kind"], "auction_house")
	assert_eq(String(net.broadcast_calls[0]["payload"]["event"]), "listings_snapshot")
	assert_eq((net.broadcast_calls[0]["payload"]["listings"] as Array).size(), 1,
		"Der gebroadcastete Snapshot muss das neue Listing enthalten.")
	# Die gezielte Bestätigung an den Verkäufer muss weiterhin zusätzlich laufen.
	assert_eq(net.send_calls.size(), 1)
	assert_eq(net.send_calls[0]["player_id"], SELLER)

func test_buy_broadcasts_listings_snapshot_to_all_peers() -> void:
	var lid := _make_listing(5, 100)
	_currency.request_add_gold(BUYER, 100)

	var net := SpyNetworkBridge.new()
	add_child_autofree(net)
	_svc.inject_network_bridge(net)

	_svc.request_buy_item(BUYER, lid)

	assert_eq(net.broadcast_calls.size(), 1,
		"Kaufen muss genau einen Broadcast an alle Peers auslösen.")
	assert_eq(String(net.broadcast_calls[0]["payload"]["event"]), "listings_snapshot")
	assert_true((net.broadcast_calls[0]["payload"]["listings"] as Array).is_empty(),
		"Das gekaufte Listing darf im gebroadcasteten Snapshot nicht mehr auftauchen.")

func test_cancel_broadcasts_listings_snapshot_to_all_peers() -> void:
	var lid := _make_listing(5, 100)

	var net := SpyNetworkBridge.new()
	add_child_autofree(net)
	_svc.inject_network_bridge(net)

	_svc.request_cancel_listing(SELLER, lid)

	assert_eq(net.broadcast_calls.size(), 1,
		"Stornieren muss genau einen Broadcast an alle Peers auslösen.")
	assert_true((net.broadcast_calls[0]["payload"]["listings"] as Array).is_empty(),
		"Das stornierte Listing darf im gebroadcasteten Snapshot nicht mehr auftauchen.")

func test_failed_purchase_does_not_broadcast() -> void:
	var lid := _make_listing(5, 100)
	# BUYER hat kein Gold -> transaction_failed statt Erfolg.
	var net := SpyNetworkBridge.new()
	add_child_autofree(net)
	_svc.inject_network_bridge(net)

	_svc.request_buy_item(BUYER, lid)

	assert_eq(net.broadcast_calls.size(), 0,
		"Ein fehlgeschlagener Kauf darf keinen Listings-Broadcast auslösen — nichts hat sich geändert.")

func test_broadcast_event_received_routes_into_listings_updated_signal() -> void:
	# Client-Seite: broadcast_event_received (ADR-042) muss denselben Effekt
	# haben wie economy_state_received — beide laufen über
	# _on_economy_state_received() in dieselbe listings_updated-Emission.
	var net := SpyNetworkBridge.new()
	add_child_autofree(net)
	_svc.inject_network_bridge(net)

	var received: Array = []
	_svc.listings_updated.connect(func(listings: Array) -> void: received.append(listings))

	net.broadcast_event_received.emit("auction_house", {
		"event": "listings_snapshot",
		"listings": [{"listing_id": "x", "seller_id": "someone-else", "item_id": ITEM_A, "quantity": 1, "price": 1}],
	})

	assert_eq(received.size(), 1,
		"broadcast_event_received muss listings_updated auslösen, exakt wie economy_state_received.")
	assert_eq((received[0] as Array).size(), 1)

# ─────────────────────────────────────────────
# request_listings_snapshot() — Round 113 Nachtrag, siehe
# method_reference_coverage.py-Fund: bisher nie direkt aufgerufen.
# ─────────────────────────────────────────────

func test_request_listings_snapshot_sends_current_listings_to_requester() -> void:
	var net := SpyNetworkBridge.new()
	add_child_autofree(net)
	_svc.inject_network_bridge(net)
	_inventory.on_item_add_confirmed(ITEM_A, 5, SELLER)
	_svc.request_list_item(SELLER, ITEM_A, 5, 100)
	net.send_calls.clear()  # Listing-Broadcast selbst ist nicht Gegenstand dieses Tests

	_svc.request_listings_snapshot(BUYER)

	assert_eq(net.send_calls.size(), 1)
	assert_eq(net.send_calls[0]["player_id"], BUYER)
	assert_eq(net.send_calls[0]["payload"]["event"], "listings_snapshot")
	assert_eq((net.send_calls[0]["payload"]["listings"] as Array).size(), 1,
		"Snapshot muss die zu diesem Zeitpunkt aktiven Listings enthalten")

func test_request_listings_snapshot_as_client_routes_via_network() -> void:
	var net := SnapshotClientSpyBridge.new()
	add_child_autofree(net)
	_svc.inject_network_bridge(net)

	_svc.request_listings_snapshot(BUYER)

	assert_eq(net.snapshot_request_calls, [BUYER])
