# res://tests/unit/test_bank_service.gd
extends GutTest

## Unit-Tests für BankService (ADR-034) — bisher ungetestet. Entstanden als
## Nebenprodukt von ADR-035 Phase 1 (Round 88), weil dort die interne
## Item-Speicherung von BankService (Dictionary[item_id, int] →
## Dictionary[item_id, ItemInstance]) migriert wurde und dafür Abdeckung
## fehlte.
##
## Strategie: BankService direkt instanziieren, mit einer ECHTEN
## InventorySystem-Instanz als Kollaborator (Tier-1-Pfad, kein SaveSystem,
## kein NetworkBridge — analog test_inventory_system.gd). CurrencyService
## ebenfalls echt (Gold-Pfade sind unverändert von dieser Migration
## betroffen, aber Deposit/Withdraw Gold laufen trotzdem mit durch, um
## Regressionen an der Konfigurationsgrenze zu fangen).
##
## Abgedeckt:
##   - Item-Deposit/Withdraw: Bestand, Fehlerfälle, Bank↔Inventar-Bewegung
##   - ItemInstance-uuid: pro Bank-Bucket-Eintrag vergeben, stabil beim Stapeln
##   - Gold-Deposit/Withdraw: Basisfälle
##   - Save-Round-Trip inkl. ItemInstance-Serialisierung

class MockItemDef extends ItemDefinition:
	func _init(p_name: String, p_max_stack: int = 99) -> void:
		display_name = p_name
		max_stack     = p_max_stack

class MockDataService extends DataService:
	func get_all_items() -> Dictionary:
		return _items

var _bank: BankService
var _inventory: InventorySystem
var _currency: CurrencyService
var _ds: MockDataService
var _bus: MockEventBus
var _save: SaveSystem

const ITEM_A := "iron_ore"
const P1 := "p1"
const P2 := "p2"

func before_each() -> void:
	_ds = MockDataService.new()
	_ds._items[ITEM_A] = MockItemDef.new("Iron Ore", 50)
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
		ServiceKeys.EVENT_BUS: _bus,
	}))

func after_each() -> void:
	_inventory.on_cleanup()
	_inventory = null
	_currency  = null
	_bank      = null

# ─────────────────────────────────────────────────────────────────────────────
# Item-Deposit
# ─────────────────────────────────────────────────────────────────────────────

func test_deposit_moves_item_from_inventory_to_bank() -> void:
	_inventory.on_item_add_confirmed(ITEM_A, 5, P1)
	_bank.on_deposit_item_confirmed(ITEM_A, 5, P1)

	assert_false(_inventory.has_item(ITEM_A, P1, 1), "Item muss aus dem Inventar entfernt sein")
	assert_eq(_bank.get_bank_items(P1).size(), 1, "Item muss in der Bank erscheinen")
	assert_eq(_bank.get_bank_items(P1)[0]["quantity"], 5)

func test_deposit_fails_when_not_owned() -> void:
	var failed := []
	_bus.bank().bank_transaction_failed.connect(func(pid, reason): failed.append(reason))
	_bank.on_deposit_item_confirmed(ITEM_A, 5, P1)  # nie im Inventar
	assert_eq(failed, ["item_not_owned"])
	assert_true(_bank.get_bank_items(P1).is_empty())

func test_deposit_stacks_onto_existing_bank_entry() -> void:
	_inventory.on_item_add_confirmed(ITEM_A, 10, P1)
	_bank.on_deposit_item_confirmed(ITEM_A, 4, P1)
	_bank.on_deposit_item_confirmed(ITEM_A, 3, P1)
	assert_eq(_bank.get_bank_items(P1)[0]["quantity"], 7, "Zwei Einzahlungen müssen sich summieren")

# ─────────────────────────────────────────────────────────────────────────────
# Item-Withdraw
# ─────────────────────────────────────────────────────────────────────────────

func test_withdraw_moves_item_from_bank_to_inventory() -> void:
	_inventory.on_item_add_confirmed(ITEM_A, 5, P1)
	_bank.on_deposit_item_confirmed(ITEM_A, 5, P1)
	_bank.on_withdraw_item_confirmed(ITEM_A, 2, P1)

	assert_true(_inventory.has_item(ITEM_A, P1, 2), "2x müssen wieder im Inventar sein")
	assert_eq(_bank.get_bank_items(P1)[0]["quantity"], 3, "3 verbleiben in der Bank")

func test_withdraw_more_than_stored_fails() -> void:
	_inventory.on_item_add_confirmed(ITEM_A, 5, P1)
	_bank.on_deposit_item_confirmed(ITEM_A, 5, P1)

	var failed := []
	_bus.bank().bank_transaction_failed.connect(func(pid, reason): failed.append(reason))
	_bank.on_withdraw_item_confirmed(ITEM_A, 99, P1)
	assert_eq(failed, ["item_not_in_bank"])
	assert_eq(_bank.get_bank_items(P1)[0]["quantity"], 5, "Bestand darf sich bei Fehlschlag nicht ändern")

func test_withdraw_full_amount_clears_bank_entry() -> void:
	_inventory.on_item_add_confirmed(ITEM_A, 5, P1)
	_bank.on_deposit_item_confirmed(ITEM_A, 5, P1)
	_bank.on_withdraw_item_confirmed(ITEM_A, 5, P1)
	assert_true(_bank.get_bank_items(P1).is_empty(), "Vollständige Abhebung muss den Eintrag entfernen")

# ─────────────────────────────────────────────────────────────────────────────
# ADR-035 Phase 1 — ItemInstance-uuid
# ─────────────────────────────────────────────────────────────────────────────

func test_bank_deposit_assigns_uuid() -> void:
	_inventory.on_item_add_confirmed(ITEM_A, 1, P1)
	_bank.on_deposit_item_confirmed(ITEM_A, 1, P1)
	var inst := _bank.get_bank_item_instance(P1, ITEM_A)
	assert_not_null(inst)
	assert_false(inst.uuid.is_empty(), "Bank-Eintrag muss eine uuid tragen")

func test_bank_uuid_stable_across_multiple_deposits() -> void:
	_inventory.on_item_add_confirmed(ITEM_A, 10, P1)
	_bank.on_deposit_item_confirmed(ITEM_A, 4, P1)
	var uuid_before := _bank.get_bank_item_instance(P1, ITEM_A).uuid
	_bank.on_deposit_item_confirmed(ITEM_A, 3, P1)
	var uuid_after := _bank.get_bank_item_instance(P1, ITEM_A).uuid
	assert_eq(uuid_after, uuid_before, "Stapeln auf einen bestehenden Bank-Eintrag darf die uuid nicht ändern")

func test_bank_uuid_differs_between_players() -> void:
	_inventory.on_item_add_confirmed(ITEM_A, 1, P1)
	_inventory.on_item_add_confirmed(ITEM_A, 1, P2)
	_bank.on_deposit_item_confirmed(ITEM_A, 1, P1)
	_bank.on_deposit_item_confirmed(ITEM_A, 1, P2)
	assert_ne(
		_bank.get_bank_item_instance(P1, ITEM_A).uuid,
		_bank.get_bank_item_instance(P2, ITEM_A).uuid,
		"Zwei Spieler dürfen keine geteilte uuid haben"
	)

# ─────────────────────────────────────────────────────────────────────────────
# Gold
# ─────────────────────────────────────────────────────────────────────────────

func test_deposit_and_withdraw_gold() -> void:
	_currency.request_add_gold(P1, 100)
	_bank.on_deposit_gold_confirmed(60, P1)
	assert_eq(_bank.get_bank_gold(P1), 60)
	assert_eq(_currency.get_gold(P1), 40)

	_bank.on_withdraw_gold_confirmed(20, P1)
	assert_eq(_bank.get_bank_gold(P1), 40)
	assert_eq(_currency.get_gold(P1), 60)

# ─────────────────────────────────────────────────────────────────────────────
# Save-Round-Trip
# ─────────────────────────────────────────────────────────────────────────────

func test_save_round_trip_preserves_items_and_uuid() -> void:
	_inventory.on_item_add_confirmed(ITEM_A, 8, P1)
	_bank.on_deposit_item_confirmed(ITEM_A, 8, P1)
	var uuid_before := _bank.get_bank_item_instance(P1, ITEM_A).uuid
	var snapshot := _bank.get_save_data()

	var bank2 := BankService.new()
	bank2.configure(ServiceDeps.from_dict({
		ServiceKeys.INVENTORY: _inventory,
		ServiceKeys.CURRENCY:  _currency,
		ServiceKeys.DATA:      _ds,
		ServiceKeys.SAVE_SYSTEM: _save,
	}))
	bank2._restore_from_save(snapshot)

	assert_eq(bank2.get_bank_items(P1)[0]["quantity"], 8)
	assert_eq(bank2.get_bank_item_instance(P1, ITEM_A).uuid, uuid_before, "Round-Trip muss die uuid erhalten")

func test_save_data_key_is_bank() -> void:
	assert_eq(_bank.get_save_key(), "bank")

# ─────────────────────────────────────────────────────────────────────────────
# Netzwerk-Routing — inject_network_bridge() + request_*() (Round 113 Nachtrag,
# siehe method_reference_coverage.py-Fund: request_*()/inject_network_bridge()
# waren bisher nie direkt aufgerufen, nur die on_*_confirmed()-Gegenstücke)
# ─────────────────────────────────────────────────────────────────────────────

class MockBridgeAsClient extends NetworkBridge:
	var deposit_item_calls: Array = []
	var withdraw_item_calls: Array = []
	var deposit_gold_calls: Array = []
	var withdraw_gold_calls: Array = []
	func has_peer() -> bool:
		return true
	func is_server() -> bool:
		return false
	func send_bank_deposit_item(item_id: String, quantity: int, player_id: String) -> void:
		deposit_item_calls.append([item_id, quantity, player_id])
	func send_bank_withdraw_item(item_id: String, quantity: int, player_id: String) -> void:
		withdraw_item_calls.append([item_id, quantity, player_id])
	func send_bank_deposit_gold(amount: int, player_id: String) -> void:
		deposit_gold_calls.append([amount, player_id])
	func send_bank_withdraw_gold(amount: int, player_id: String) -> void:
		withdraw_gold_calls.append([amount, player_id])

func test_inject_network_bridge_sets_the_reference() -> void:
	var bridge: NetworkBridge = add_child_autofree(NetworkBridge.new())
	_bank.inject_network_bridge(bridge)
	assert_same(_bank._network, bridge)

func test_request_deposit_item_without_network_confirms_directly() -> void:
	# Kein inject_network_bridge() -> _network bleibt null -> request_*() muss
	# denselben Effekt wie ein direkter on_*_confirmed()-Aufruf haben (Solo-/
	# Host-Pfad, siehe Klassenkommentar "NICHT wie InventorySystem").
	_inventory.on_item_add_confirmed(ITEM_A, 5, P1)
	_bank.request_deposit_item(P1, ITEM_A, 5)
	assert_eq(_bank.get_bank_items(P1).size(), 1, "Ohne Network-Bridge muss request_deposit_item() sofort einzahlen")

func test_request_deposit_item_as_client_routes_via_network_not_local() -> void:
	var bridge: MockBridgeAsClient = add_child_autofree(MockBridgeAsClient.new())
	_bank.inject_network_bridge(bridge)
	_inventory.on_item_add_confirmed(ITEM_A, 5, P1)

	_bank.request_deposit_item(P1, ITEM_A, 5)

	assert_eq(bridge.deposit_item_calls, [[ITEM_A, 5, P1]], "Als Client muss request_deposit_item() über die Bridge geroutet werden")
	assert_true(_bank.get_bank_items(P1).is_empty(), "Auf dem Client darf NICHT direkt eingezahlt werden — das macht erst die Autorität")

func test_request_withdraw_item_as_client_routes_via_network_not_local() -> void:
	var bridge: MockBridgeAsClient = add_child_autofree(MockBridgeAsClient.new())
	_inventory.on_item_add_confirmed(ITEM_A, 5, P1)
	_bank.on_deposit_item_confirmed(ITEM_A, 5, P1)  # Bank-Bestand als Autorität aufbauen, VOR dem Bridge-Inject
	_bank.inject_network_bridge(bridge)

	_bank.request_withdraw_item(P1, ITEM_A, 2)

	assert_eq(bridge.withdraw_item_calls, [[ITEM_A, 2, P1]])
	assert_eq(_bank.get_bank_items(P1)[0]["quantity"], 5, "Auf dem Client darf sich der Bank-Bestand nicht ändern")

func test_request_deposit_gold_as_client_routes_via_network_not_local() -> void:
	var bridge: MockBridgeAsClient = add_child_autofree(MockBridgeAsClient.new())
	_bank.inject_network_bridge(bridge)
	_currency.request_add_gold(P1, 100)

	_bank.request_deposit_gold(P1, 50)

	assert_eq(bridge.deposit_gold_calls, [[50, P1]])
	assert_eq(_bank.get_bank_gold(P1), 0, "Auf dem Client darf kein Gold direkt eingezahlt werden")

func test_request_withdraw_gold_as_client_routes_via_network_not_local() -> void:
	var bridge: MockBridgeAsClient = add_child_autofree(MockBridgeAsClient.new())
	_currency.request_add_gold(P1, 100)
	_bank.on_deposit_gold_confirmed(50, P1)
	_bank.inject_network_bridge(bridge)

	_bank.request_withdraw_gold(P1, 20)

	assert_eq(bridge.withdraw_gold_calls, [[20, P1]])
	assert_eq(_bank.get_bank_gold(P1), 50, "Auf dem Client darf sich der Bank-Bestand nicht ändern")

# ─────────────────────────────────────────────────────────────────────────────
# Auktionshaus-Escrow — remove_item_for_listing() / add_item_to_bank()
# (Round 113 Nachtrag)
# ─────────────────────────────────────────────────────────────────────────────

func test_remove_item_for_listing_moves_item_out_of_bank() -> void:
	_inventory.on_item_add_confirmed(ITEM_A, 5, P1)
	_bank.on_deposit_item_confirmed(ITEM_A, 5, P1)

	var ok := _bank.remove_item_for_listing(P1, ITEM_A, 3)

	assert_true(ok)
	assert_eq(_bank.get_bank_items(P1)[0]["quantity"], 2, "Anders als withdraw geht es NICHT zurück ins Inventar")
	assert_false(_inventory.has_item(ITEM_A, P1, 1), "Item darf nicht im Inventar landen — Escrow, kein Withdraw")

func test_remove_item_for_listing_full_amount_clears_entry() -> void:
	_inventory.on_item_add_confirmed(ITEM_A, 5, P1)
	_bank.on_deposit_item_confirmed(ITEM_A, 5, P1)

	_bank.remove_item_for_listing(P1, ITEM_A, 5)

	assert_true(_bank.get_bank_items(P1).is_empty())

func test_remove_item_for_listing_more_than_stored_fails_without_mutation() -> void:
	_inventory.on_item_add_confirmed(ITEM_A, 5, P1)
	_bank.on_deposit_item_confirmed(ITEM_A, 5, P1)

	var ok := _bank.remove_item_for_listing(P1, ITEM_A, 99)

	assert_false(ok)
	assert_eq(_bank.get_bank_items(P1)[0]["quantity"], 5, "Bei fehlgeschlagener Entnahme darf sich der Bestand nicht ändern")

func test_remove_item_for_listing_denied_on_client() -> void:
	var bridge: MockBridgeAsClient = add_child_autofree(MockBridgeAsClient.new())
	_inventory.on_item_add_confirmed(ITEM_A, 5, P1)
	_bank.on_deposit_item_confirmed(ITEM_A, 5, P1)
	_bank.inject_network_bridge(bridge)

	var ok := _bank.remove_item_for_listing(P1, ITEM_A, 3)

	assert_false(ok, "_require_authority() muss auf dem Client verweigern")
	assert_eq(_bank.get_bank_items(P1)[0]["quantity"], 5, "Kein Bestand darf sich auf dem Client ändern")

func test_add_item_to_bank_restores_a_cancelled_listing() -> void:
	var def: ItemDefinition = _ds._items[ITEM_A]
	_bank.add_item_to_bank(P1, ITEM_A, 4, def)
	assert_eq(_bank.get_bank_items(P1)[0]["quantity"], 4)

func test_add_item_to_bank_stacks_onto_existing_entry() -> void:
	var def: ItemDefinition = _ds._items[ITEM_A]
	_bank.add_item_to_bank(P1, ITEM_A, 4, def)
	_bank.add_item_to_bank(P1, ITEM_A, 3, def)
	assert_eq(_bank.get_bank_items(P1)[0]["quantity"], 7)

func test_add_item_to_bank_denied_on_client() -> void:
	var bridge: MockBridgeAsClient = add_child_autofree(MockBridgeAsClient.new())
	_bank.inject_network_bridge(bridge)
	var def: ItemDefinition = _ds._items[ITEM_A]

	_bank.add_item_to_bank(P1, ITEM_A, 4, def)

	assert_true(_bank.get_bank_items(P1).is_empty(), "_require_authority() muss auf dem Client verweigern, kein stiller Erfolg")
