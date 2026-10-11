# res://tests/unit/test_shop_service.gd
extends GutTest

## Unit-Tests für ShopService (Round 88, Trading-ADR-035-Vorstufe).
##
## Strategie: ShopService extends Service (RefCounted) — kein add_child nötig.
## CurrencyService wird ECHT instanziiert (einfach, gut verstanden, siehe
## test_currency_service.gd — hier will man den echten Gold-Rollback-Pfad
## sehen, nicht einen Stub der ihn wegabstrahiert). InventorySystem und
## DataService dagegen als leichte lokale Stubs (gleiches Muster wie in
## test_reward_dispatcher.gd) — beide bräuchten für echte Instanzen deutlich
## mehr Setup (Gewichtslimits, ItemDefinition-Manifeste von Disk) für Dinge,
## die hier nicht getestet werden sollen; ShopService selbst ist das Objekt
## unter Test, nicht seine Kollaboratoren.
##
## Kein NetworkBridge konfiguriert -> _network bleibt null -> request_buy_item()/
## request_sell_item() nehmen IMMER den synchronen else-Zweig direkt zu
## on_*_confirmed() (Tier-1-Pfad, analog "kein Peer" in test_currency_service.gd).
## Den Nicht-Autorität-Guard in on_buy_confirmed()/on_sell_confirmed() (der
## einen echten MultiplayerPeer bräuchte) testet dieses File bewusst nicht.
##
## Abgedeckt:
##   - get_buy_price()/is_buyable(): Katalog-Items, unbekannte Items
##   - get_sell_price(): DataService-Preis, Fallback DEFAULT_SELL_PRICE bei 0,
##     unbekanntes Item (kein ItemDefinition) -> 0
##   - Kaufen: Erfolgsfall, quantity<=0, nicht käuflich, zu wenig Gold,
##     Inventar voll -> Gold-Rollback
##   - Verkaufen: Erfolgsfall, quantity<=0, Item nicht besessen,
##     remove_item() schlägt trotz has_item()==true fehl (Race-Fall)
##   - Signal-Payloads: purchase_completed/sale_completed/transaction_failed

const PLAYER_ID := "player-uuid-1"


class StubInventorySystem extends InventorySystem:
	var add_item_result: bool = true
	var has_item_result: bool = true
	var remove_item_result: bool = true
	var add_item_calls: Array = []
	var has_item_calls: Array = []
	var remove_item_calls: Array = []

	func request_add_item(item_id: String, player_id: String, quantity: int = 1) -> bool:
		add_item_calls.append([item_id, player_id, quantity])
		return add_item_result

	func has_item(item_id: String, player_id: String, quantity: int = 1) -> bool:
		has_item_calls.append([item_id, player_id, quantity])
		return has_item_result

	func remove_item(item_id: String, player_id: String, quantity: int = 1) -> bool:
		remove_item_calls.append([item_id, player_id, quantity])
		return remove_item_result


class StubDataService extends DataService:
	var items: Dictionary = {}  ## item_id -> ItemDefinition
	func get_item(item_id: String) -> ItemDefinition:
		return items.get(item_id)


var _svc: ShopService
var _currency: CurrencyService
var _inventory: StubInventorySystem
var _data: StubDataService
var _bus: MockEventBus


func before_each() -> void:
	_bus = MockEventBus.new()

	_currency = CurrencyService.new()
	_currency.configure(ServiceDeps.from_dict({ServiceKeys.EVENT_BUS: _bus}))

	_inventory = StubInventorySystem.new()
	_data = StubDataService.new()

	_svc = ShopService.new()
	_svc.configure(ServiceDeps.from_dict({
		ServiceKeys.INVENTORY: _inventory,
		ServiceKeys.CURRENCY: _currency,
		ServiceKeys.DATA: _data,
		ServiceKeys.EVENT_BUS: _bus,
	}))


func after_each() -> void:
	_currency.on_cleanup()
	_svc = null
	_currency = null
	_inventory = null
	_data = null
	_bus = null


func _make_item(item_id: String, sell_price: int) -> ItemDefinition:
	var d := ItemDefinition.new()
	d.id = item_id
	d.sell_price = sell_price
	return d


# ─────────────────────────────────────────────
# get_buy_price() / is_buyable()
# ─────────────────────────────────────────────

func test_get_buy_price_known_catalog_item() -> void:
	assert_eq(_svc.get_buy_price("tool_axe"), 25)
	assert_eq(_svc.get_buy_price("tool_pickaxe"), 30)

func test_get_buy_price_unknown_item_is_negative_one() -> void:
	assert_eq(_svc.get_buy_price("does_not_exist"), -1)

func test_is_buyable_true_for_catalog_item() -> void:
	assert_true(_svc.is_buyable("tool_axe"))

func test_is_buyable_false_for_unknown_item() -> void:
	assert_false(_svc.is_buyable("does_not_exist"))

# Round 94: ADR-038/ADR-039 Beschaffung über den bestehenden ShopService.
func test_get_buy_price_adr038_scrolls() -> void:
	assert_eq(_svc.get_buy_price("scroll_pve_protection"), 40)
	assert_eq(_svc.get_buy_price("scroll_theft_protection"), 40)
	assert_eq(_svc.get_buy_price("scroll_pvp_protection"), 80)

func test_get_buy_price_adr039_theft_crystals() -> void:
	assert_eq(_svc.get_buy_price("theft_crystal_weak"), 15)
	assert_eq(_svc.get_buy_price("theft_crystal_normal"), 60)
	assert_eq(_svc.get_buy_price("theft_crystal_strong"), 400)

func test_is_buyable_true_for_all_adr038_adr039_items() -> void:
	for item_id in [
		"scroll_pve_protection", "scroll_theft_protection", "scroll_pvp_protection",
		"theft_crystal_weak", "theft_crystal_normal", "theft_crystal_strong",
	]:
		assert_true(_svc.is_buyable(item_id), "'%s' sollte käuflich sein." % item_id)

func test_buy_scroll_pve_protection_deducts_gold_and_adds_item() -> void:
	_currency.request_add_gold(PLAYER_ID, 100)
	_svc.request_buy_item(PLAYER_ID, "scroll_pve_protection", 1)
	assert_eq(_currency.get_gold(PLAYER_ID), 60, "100 - 40 (scroll_pve_protection) = 60.")
	assert_eq(_inventory.add_item_calls[-1], ["scroll_pve_protection", PLAYER_ID, 1])

func test_buy_theft_crystal_strong_deducts_gold_and_adds_item() -> void:
	_currency.request_add_gold(PLAYER_ID, 500)
	_svc.request_buy_item(PLAYER_ID, "theft_crystal_strong", 1)
	assert_eq(_currency.get_gold(PLAYER_ID), 100, "500 - 400 (theft_crystal_strong) = 100.")
	assert_eq(_inventory.add_item_calls[-1], ["theft_crystal_strong", PLAYER_ID, 1])


# ─────────────────────────────────────────────
# get_sell_price()
# ─────────────────────────────────────────────

func test_get_sell_price_uses_item_definition_price() -> void:
	_data.items["iron_ore"] = _make_item("iron_ore", 5)
	assert_eq(_svc.get_sell_price("iron_ore"), 5)

func test_get_sell_price_falls_back_to_default_when_zero() -> void:
	_data.items["junk"] = _make_item("junk", 0)
	assert_eq(_svc.get_sell_price("junk"), ShopService.DEFAULT_SELL_PRICE)

func test_get_sell_price_unknown_item_is_zero() -> void:
	assert_eq(_svc.get_sell_price("does_not_exist"), 0)


# ─────────────────────────────────────────────
# Kaufen — request_buy_item() / on_buy_confirmed()
# ─────────────────────────────────────────────

func test_buy_success_deducts_gold_and_adds_item() -> void:
	_currency.request_add_gold(PLAYER_ID, 100)
	_svc.request_buy_item(PLAYER_ID, "tool_axe", 1)
	assert_eq(_currency.get_gold(PLAYER_ID), 75, "100 - 25 (tool_axe) = 75.")
	assert_eq(_inventory.add_item_calls.size(), 1)
	assert_eq(_inventory.add_item_calls[0], ["tool_axe", PLAYER_ID, 1])

func test_buy_success_emits_purchase_completed_with_total_price() -> void:
	_currency.request_add_gold(PLAYER_ID, 100)
	var received: Array = []
	_bus.shop().shop_transaction_purchase_completed.connect(func(pid, item_id, qty, total): received.append([pid, item_id, qty, total]))
	_svc.request_buy_item(PLAYER_ID, "tool_axe", 2)
	assert_eq(received.size(), 1)
	assert_eq(received[0], [PLAYER_ID, "tool_axe", 2, 50], "2x tool_axe a 25 = 50 total_price.")

func test_buy_quantity_zero_fails_without_side_effects() -> void:
	_currency.request_add_gold(PLAYER_ID, 100)
	var failed: Array = []
	_bus.shop().shop_transaction_failed.connect(func(pid, reason): failed.append([pid, reason]))
	_svc.request_buy_item(PLAYER_ID, "tool_axe", 0)
	assert_eq(failed, [[PLAYER_ID, "invalid_quantity"]])
	assert_eq(_currency.get_gold(PLAYER_ID), 100, "Gold darf sich bei ungültiger Menge nicht ändern.")
	assert_eq(_inventory.add_item_calls.size(), 0)

func test_buy_item_not_in_catalog_fails() -> void:
	_currency.request_add_gold(PLAYER_ID, 100)
	var failed: Array = []
	_bus.shop().shop_transaction_failed.connect(func(pid, reason): failed.append([pid, reason]))
	_svc.request_buy_item(PLAYER_ID, "not_for_sale_item", 1)
	assert_eq(failed, [[PLAYER_ID, "not_for_sale"]])
	assert_eq(_inventory.add_item_calls.size(), 0)

func test_buy_insufficient_gold_fails_without_touching_inventory() -> void:
	_currency.request_add_gold(PLAYER_ID, 10)  # tool_axe kostet 25
	var failed: Array = []
	_bus.shop().shop_transaction_failed.connect(func(pid, reason): failed.append([pid, reason]))
	_svc.request_buy_item(PLAYER_ID, "tool_axe", 1)
	assert_eq(failed, [[PLAYER_ID, "insufficient_gold"]])
	assert_eq(_currency.get_gold(PLAYER_ID), 10, "Gold unverändert bei abgelehntem Kauf.")
	assert_eq(_inventory.add_item_calls.size(), 0)

func test_buy_inventory_full_rolls_back_gold() -> void:
	_currency.request_add_gold(PLAYER_ID, 100)
	_inventory.add_item_result = false  # simuliert volles Inventar
	var failed: Array = []
	_bus.shop().shop_transaction_failed.connect(func(pid, reason): failed.append([pid, reason]))
	_svc.request_buy_item(PLAYER_ID, "tool_axe", 1)
	assert_eq(failed, [[PLAYER_ID, "inventory_full"]])
	assert_eq(_currency.get_gold(PLAYER_ID), 100, "Gold muss nach fehlgeschlagenem Inventar-Add vollständig zurückerstattet werden.")


# ─────────────────────────────────────────────
# Verkaufen — request_sell_item() / on_sell_confirmed()
# ─────────────────────────────────────────────

func test_sell_success_adds_gold_and_removes_item() -> void:
	_data.items["iron_ore"] = _make_item("iron_ore", 5)
	_svc.request_sell_item(PLAYER_ID, "iron_ore", 3)
	assert_eq(_currency.get_gold(PLAYER_ID), 15, "3x 5 Gold = 15.")
	assert_eq(_inventory.remove_item_calls.size(), 1)
	assert_eq(_inventory.remove_item_calls[0], ["iron_ore", PLAYER_ID, 3])

func test_sell_success_emits_sale_completed_with_total_price() -> void:
	_data.items["iron_ore"] = _make_item("iron_ore", 5)
	var received: Array = []
	_svc.sale_completed.connect(func(pid, item_id, qty, total): received.append([pid, item_id, qty, total]))
	_svc.request_sell_item(PLAYER_ID, "iron_ore", 3)
	assert_eq(received, [[PLAYER_ID, "iron_ore", 3, 15]])

func test_sell_uses_default_price_for_unset_sell_price() -> void:
	_data.items["junk"] = _make_item("junk", 0)
	_svc.request_sell_item(PLAYER_ID, "junk", 1)
	assert_eq(_currency.get_gold(PLAYER_ID), ShopService.DEFAULT_SELL_PRICE)

func test_sell_quantity_zero_fails_without_side_effects() -> void:
	var failed: Array = []
	_bus.shop().shop_transaction_failed.connect(func(pid, reason): failed.append([pid, reason]))
	_svc.request_sell_item(PLAYER_ID, "iron_ore", 0)
	assert_eq(failed, [[PLAYER_ID, "invalid_quantity"]])
	assert_eq(_inventory.remove_item_calls.size(), 0)

func test_sell_item_not_owned_fails() -> void:
	_inventory.has_item_result = false
	var failed: Array = []
	_bus.shop().shop_transaction_failed.connect(func(pid, reason): failed.append([pid, reason]))
	_svc.request_sell_item(PLAYER_ID, "iron_ore", 1)
	assert_eq(failed, [[PLAYER_ID, "item_not_owned"]])
	assert_eq(_inventory.remove_item_calls.size(), 0, "has_item()==false darf remove_item() gar nicht erst aufrufen.")
	assert_eq(_currency.get_gold(PLAYER_ID), 0, "Kein Gold ohne tatsächlich verkauftes Item.")

func test_sell_remove_item_fails_despite_has_item_true_yields_item_not_owned() -> void:
	# Race-Fall laut Code: has_item() sagt ja, remove_item() schlägt trotzdem
	# fehl (z.B. durch eine Mutation zwischen beiden Aufrufen) -> derselbe
	# "item_not_owned"-Grund, kein separater Fehlercode dafür im Service.
	_inventory.has_item_result = true
	_inventory.remove_item_result = false
	var failed: Array = []
	_bus.shop().shop_transaction_failed.connect(func(pid, reason): failed.append([pid, reason]))
	_svc.request_sell_item(PLAYER_ID, "iron_ore", 1)
	assert_eq(failed, [[PLAYER_ID, "item_not_owned"]])
	assert_eq(_currency.get_gold(PLAYER_ID), 0, "Kein Gold-Gutschrift wenn remove_item() fehlschlägt.")

# ─────────────────────────────────────────────
# Netzwerk-Routing — inject_network_bridge() (Round 113 Nachtrag, siehe
# method_reference_coverage.py-Fund)
# ─────────────────────────────────────────────

class MockBridgeAsClient extends NetworkBridge:
	var buy_calls: Array = []
	var sell_calls: Array = []
	func has_peer() -> bool:
		return true
	func is_server() -> bool:
		return false
	func send_shop_buy_item(item_id: String, quantity: int, player_id: String) -> void:
		buy_calls.append([item_id, quantity, player_id])
	func send_shop_sell_item(item_id: String, quantity: int, player_id: String) -> void:
		sell_calls.append([item_id, quantity, player_id])

func test_inject_network_bridge_sets_the_reference() -> void:
	var bridge: NetworkBridge = add_child_autofree(NetworkBridge.new())
	_svc.inject_network_bridge(bridge)
	assert_same(_svc._network, bridge)

func test_request_buy_item_as_client_routes_via_network_not_local() -> void:
	var bridge: MockBridgeAsClient = add_child_autofree(MockBridgeAsClient.new())
	_svc.inject_network_bridge(bridge)

	_svc.request_buy_item(PLAYER_ID, "tool_axe", 1)

	assert_eq(bridge.buy_calls, [["tool_axe", 1, PLAYER_ID]])
	assert_eq(_inventory.add_item_calls.size(), 0, "Auf dem Client darf nicht direkt gekauft werden")

func test_request_sell_item_as_client_routes_via_network_not_local() -> void:
	var bridge: MockBridgeAsClient = add_child_autofree(MockBridgeAsClient.new())
	_svc.inject_network_bridge(bridge)

	_svc.request_sell_item(PLAYER_ID, "iron_ore", 1)

	assert_eq(bridge.sell_calls, [["iron_ore", 1, PLAYER_ID]])
	assert_eq(_inventory.remove_item_calls.size(), 0, "Auf dem Client darf nicht direkt verkauft werden")
