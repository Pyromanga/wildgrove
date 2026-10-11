# res://tests/unit/test_item_protection_service.gd
extends GutTest

## Unit-Tests für ItemProtectionService (ADR-038) — Item-Schutz-Dreiklang.
##
## Strategie: ItemProtectionService direkt instanziieren, mit einer ECHTEN
## InventorySystem-Instanz als Kollaborator (Tier-1-Pfad, kein SaveSystem, kein
## NetworkBridge) — analog test_bank_service.gd/test_shop_service.gd.
##
## Abgedeckt:
##   - Anwendung: Erfolg für alle drei protection_type-Werte, Scroll wird
##     konsumiert, NUR das richtige Flag wird gesetzt
##   - Sicherheits-Eigenschaft: protection_type kommt AUSSCHLIESSLICH aus der
##     ItemDefinition des Scrolls, nicht aus einem Aufrufer-Parameter (die API
##     hat dafür schlicht keinen Parameter — Test prüft das Verhalten trotzdem
##     end-to-end: zwei verschiedene Scrolls auf dasselbe Ziel ergeben zwei
##     verschiedene, unabhängige Flags)
##   - Fehlerfälle: unbekanntes Scroll, normales Item als "Scroll" eingereicht,
##     Scroll nicht im Bestand, Ziel nicht im Bestand, Ziel==Scroll,
##     bereits geschützt (kein doppeltes Setzen)
##   - is_protected_from(): alle drei threat_types + unbekannter Typ
##   - consume_pvp_protection(): verbraucht genau einmal, false wenn nichts da
##   - PvE-/Diebstahlschutz bleiben nach consume_pvp_protection() unberührt
##     (unabhängige Lebenszyklen, ADR-Kernaussage)

class MockItemDef extends ItemDefinition:
	func _init(p_id: String, p_name: String, p_protection_type: String = "", p_max_stack: int = 99) -> void:
		id = p_id
		display_name = p_name
		max_stack = p_max_stack
		grants_protection_type = p_protection_type

class MockDataService extends DataService:
	func get_all_items() -> Dictionary:
		return _items

var _protection: ItemProtectionService
var _inventory: InventorySystem
var _ds: MockDataService
var _bus: MockEventBus

const SCROLL_PVE   := "scroll_pve_protection"
const SCROLL_THEFT := "scroll_theft_protection"
const SCROLL_PVP   := "scroll_pvp_protection"
const SWORD        := "iron_sword"
const P1 := "p1"
const P2 := "p2"

func before_each() -> void:
	_ds = MockDataService.new()
	_ds._items[SCROLL_PVE]   = MockItemDef.new(SCROLL_PVE,   "Schutzscroll (PvE)",   "pve",   20)
	_ds._items[SCROLL_THEFT] = MockItemDef.new(SCROLL_THEFT, "Schutzscroll (Diebstahl)", "theft", 20)
	_ds._items[SCROLL_PVP]   = MockItemDef.new(SCROLL_PVP,   "Schutzscroll (PvP)",   "pvp",   20)
	_ds._items[SWORD]        = MockItemDef.new(SWORD, "Eisenschwert", "", 1)
	_bus = MockEventBus.new()

	_inventory = InventorySystem.new()
	_inventory.configure(ServiceDeps.from_dict({
		ServiceKeys.DATA:      _ds,
		ServiceKeys.EVENT_BUS: _bus,
	}))

	_protection = ItemProtectionService.new()
	_protection.configure(ServiceDeps.from_dict({
		ServiceKeys.INVENTORY: _inventory,
	}))

func after_each() -> void:
	_inventory.on_cleanup()
	_inventory  = null
	_protection = null

# ─────────────────────────────────────────────────────────────────────────────
# Anwendung — Erfolg
# ─────────────────────────────────────────────────────────────────────────────

func test_apply_pve_protection_sets_flag_and_consumes_scroll() -> void:
	_inventory.on_item_add_confirmed(SWORD, 1, P1)
	_inventory.on_item_add_confirmed(SCROLL_PVE, 1, P1)

	_protection.on_apply_protection_confirmed(SCROLL_PVE, SWORD, P1)

	var inst := _inventory.get_item_instance(P1, SWORD)
	assert_true(inst.is_pve_death_protected, "PvE-Schutz muss gesetzt sein")
	assert_false(inst.is_theft_protected, "Diebstahlschutz darf NICHT gesetzt sein")
	assert_false(inst.is_pvp_protected, "PvP-Schutz darf NICHT gesetzt sein")
	assert_false(_inventory.has_item(SCROLL_PVE, P1, 1), "Scroll muss verbraucht sein")

func test_apply_theft_protection_sets_only_theft_flag() -> void:
	_inventory.on_item_add_confirmed(SWORD, 1, P1)
	_inventory.on_item_add_confirmed(SCROLL_THEFT, 1, P1)
	_protection.on_apply_protection_confirmed(SCROLL_THEFT, SWORD, P1)
	var inst := _inventory.get_item_instance(P1, SWORD)
	assert_true(inst.is_theft_protected)
	assert_false(inst.is_pve_death_protected)
	assert_false(inst.is_pvp_protected)

func test_apply_pvp_protection_sets_only_pvp_flag() -> void:
	_inventory.on_item_add_confirmed(SWORD, 1, P1)
	_inventory.on_item_add_confirmed(SCROLL_PVP, 1, P1)
	_protection.on_apply_protection_confirmed(SCROLL_PVP, SWORD, P1)
	var inst := _inventory.get_item_instance(P1, SWORD)
	assert_true(inst.is_pvp_protected)
	assert_false(inst.is_pve_death_protected)
	assert_false(inst.is_theft_protected)

func test_apply_emits_protection_applied_signal() -> void:
	_inventory.on_item_add_confirmed(SWORD, 1, P1)
	_inventory.on_item_add_confirmed(SCROLL_PVE, 1, P1)
	var received := []
	_protection.protection_applied.connect(func(pid, item_id, ptype): received.append([pid, item_id, ptype]))
	_protection.on_apply_protection_confirmed(SCROLL_PVE, SWORD, P1)
	assert_eq(received, [[P1, SWORD, "pve"]])

func test_two_different_scrolls_on_same_target_set_independent_flags() -> void:
	# Kernaussage der ADR: drei unabhängige Lebenszyklen, nicht ein Flag.
	_inventory.on_item_add_confirmed(SWORD, 1, P1)
	_inventory.on_item_add_confirmed(SCROLL_PVE, 1, P1)
	_inventory.on_item_add_confirmed(SCROLL_PVP, 1, P1)
	_protection.on_apply_protection_confirmed(SCROLL_PVE, SWORD, P1)
	_protection.on_apply_protection_confirmed(SCROLL_PVP, SWORD, P1)
	var inst := _inventory.get_item_instance(P1, SWORD)
	assert_true(inst.is_pve_death_protected)
	assert_true(inst.is_pvp_protected)
	assert_false(inst.is_theft_protected)

# ─────────────────────────────────────────────────────────────────────────────
# Anwendung — Fehlerfälle
# ─────────────────────────────────────────────────────────────────────────────

func test_apply_fails_for_unknown_scroll_id() -> void:
	_inventory.on_item_add_confirmed(SWORD, 1, P1)
	var failed := []
	_protection.application_failed.connect(func(pid, reason): failed.append(reason))
	_protection.on_apply_protection_confirmed("does_not_exist", SWORD, P1)
	assert_eq(failed, ["unknown_scroll"])

func test_apply_fails_when_item_has_no_protection_type() -> void:
	# Ein normales Item (leeres grants_protection_type) darf nicht als "Scroll" missbraucht werden.
	_ds._items["shield"] = MockItemDef.new("shield", "Schild", "", 1)
	_inventory.on_item_add_confirmed(SWORD, 1, P1)
	_inventory.on_item_add_confirmed("shield", 1, P1)
	var failed := []
	_protection.application_failed.connect(func(pid, reason): failed.append(reason))
	_protection.on_apply_protection_confirmed(SWORD, "shield", P1)
	assert_eq(failed, ["not_a_protection_scroll"])

func test_apply_fails_when_scroll_not_owned() -> void:
	_inventory.on_item_add_confirmed(SWORD, 1, P1)
	# SCROLL_PVE nie hinzugefügt
	var failed := []
	_protection.application_failed.connect(func(pid, reason): failed.append(reason))
	_protection.on_apply_protection_confirmed(SCROLL_PVE, SWORD, P1)
	assert_eq(failed, ["scroll_not_owned"])
	assert_false(_inventory.get_item_instance(P1, SWORD).is_pve_death_protected)

func test_apply_fails_when_target_not_owned() -> void:
	_inventory.on_item_add_confirmed(SCROLL_PVE, 1, P1)
	# SWORD nie hinzugefügt
	var failed := []
	_protection.application_failed.connect(func(pid, reason): failed.append(reason))
	_protection.on_apply_protection_confirmed(SCROLL_PVE, SWORD, P1)
	assert_eq(failed, ["target_not_owned"])
	assert_true(_inventory.has_item(SCROLL_PVE, P1, 1), "Scroll darf bei Fehlschlag nicht verbraucht werden")

func test_apply_fails_when_target_is_scroll_itself() -> void:
	_inventory.on_item_add_confirmed(SCROLL_PVE, 1, P1)
	var failed := []
	_protection.application_failed.connect(func(pid, reason): failed.append(reason))
	_protection.on_apply_protection_confirmed(SCROLL_PVE, SCROLL_PVE, P1)
	assert_eq(failed, ["cannot_target_scroll_itself"])

func test_apply_fails_when_already_protected_same_type() -> void:
	_inventory.on_item_add_confirmed(SWORD, 1, P1)
	_inventory.on_item_add_confirmed(SCROLL_PVE, 2, P1)
	_protection.on_apply_protection_confirmed(SCROLL_PVE, SWORD, P1)

	var failed := []
	_protection.application_failed.connect(func(pid, reason): failed.append(reason))
	_protection.on_apply_protection_confirmed(SCROLL_PVE, SWORD, P1)
	assert_eq(failed, ["already_protected"])
	assert_true(_inventory.has_item(SCROLL_PVE, P1, 1), "Zweites Scroll darf nicht verbraucht werden")

func test_apply_does_not_cross_player_buckets() -> void:
	_inventory.on_item_add_confirmed(SWORD, 1, P2)
	_inventory.on_item_add_confirmed(SCROLL_PVE, 1, P1)  # P1 hat das Scroll, nicht P2
	var failed := []
	_protection.application_failed.connect(func(pid, reason): failed.append(reason))
	_protection.on_apply_protection_confirmed(SCROLL_PVE, SWORD, P1)  # Ziel gehört P2, nicht P1
	assert_eq(failed, ["target_not_owned"])

# ─────────────────────────────────────────────────────────────────────────────
# is_protected_from()
# ─────────────────────────────────────────────────────────────────────────────

func test_is_protected_from_false_for_unowned_item() -> void:
	assert_false(_protection.is_protected_from(P1, SWORD, ItemProtectionService.TYPE_PVE))

func test_is_protected_from_true_after_apply() -> void:
	_inventory.on_item_add_confirmed(SWORD, 1, P1)
	_inventory.on_item_add_confirmed(SCROLL_THEFT, 1, P1)
	_protection.on_apply_protection_confirmed(SCROLL_THEFT, SWORD, P1)
	assert_true(_protection.is_protected_from(P1, SWORD, ItemProtectionService.TYPE_THEFT))
	assert_false(_protection.is_protected_from(P1, SWORD, ItemProtectionService.TYPE_PVE))

func test_is_protected_from_unknown_threat_type_returns_false() -> void:
	_inventory.on_item_add_confirmed(SWORD, 1, P1)
	assert_false(_protection.is_protected_from(P1, SWORD, "unknown_threat"))

# ─────────────────────────────────────────────────────────────────────────────
# consume_pvp_protection() — für künftiges ADR-036
# ─────────────────────────────────────────────────────────────────────────────

func test_consume_pvp_protection_clears_flag_once() -> void:
	_inventory.on_item_add_confirmed(SWORD, 1, P1)
	_inventory.on_item_add_confirmed(SCROLL_PVP, 1, P1)
	_protection.on_apply_protection_confirmed(SCROLL_PVP, SWORD, P1)

	var consumed := _protection.consume_pvp_protection(P1, SWORD)
	assert_true(consumed)
	assert_false(_protection.is_protected_from(P1, SWORD, ItemProtectionService.TYPE_PVP))

	var consumed_again := _protection.consume_pvp_protection(P1, SWORD)
	assert_false(consumed_again, "Ein bereits verbrauchter Schutz darf kein zweites Mal greifen")

func test_consume_pvp_protection_false_when_never_protected() -> void:
	_inventory.on_item_add_confirmed(SWORD, 1, P1)
	assert_false(_protection.consume_pvp_protection(P1, SWORD))

func test_consume_pvp_protection_leaves_pve_and_theft_untouched() -> void:
	# Kernaussage ADR: die drei Lebenszyklen sind unabhängig — Verbrauch von
	# PvP-Schutz darf permanente Schutzarten nicht berühren.
	_inventory.on_item_add_confirmed(SWORD, 1, P1)
	_inventory.on_item_add_confirmed(SCROLL_PVE, 1, P1)
	_inventory.on_item_add_confirmed(SCROLL_PVP, 1, P1)
	_protection.on_apply_protection_confirmed(SCROLL_PVE, SWORD, P1)
	_protection.on_apply_protection_confirmed(SCROLL_PVP, SWORD, P1)

	_protection.consume_pvp_protection(P1, SWORD)

	assert_true(_protection.is_protected_from(P1, SWORD, ItemProtectionService.TYPE_PVE),
		"PvE-Schutz muss permanent bleiben, unabhängig vom PvP-Verbrauch")

func test_consume_pvp_protection_emits_signal() -> void:
	_inventory.on_item_add_confirmed(SWORD, 1, P1)
	_inventory.on_item_add_confirmed(SCROLL_PVP, 1, P1)
	_protection.on_apply_protection_confirmed(SCROLL_PVP, SWORD, P1)
	var received := []
	_protection.pvp_protection_consumed.connect(func(pid, item_id): received.append([pid, item_id]))
	_protection.consume_pvp_protection(P1, SWORD)
	assert_eq(received, [[P1, SWORD]])

# ─────────────────────────────────────────────
# Netzwerk-Routing — inject_network_bridge()/request_apply_protection()
# (Round 113 Nachtrag, siehe method_reference_coverage.py-Fund)
# ─────────────────────────────────────────────

class MockBridgeAsClient extends NetworkBridge:
	var apply_calls: Array = []
	func has_peer() -> bool:
		return true
	func is_server() -> bool:
		return false
	func send_item_protection_apply(scroll_item_id: String, target_item_id: String, player_id: String) -> void:
		apply_calls.append([scroll_item_id, target_item_id, player_id])

func test_inject_network_bridge_sets_the_reference() -> void:
	var bridge: NetworkBridge = add_child_autofree(NetworkBridge.new())
	_protection.inject_network_bridge(bridge)
	assert_same(_protection._network, bridge)

func test_request_apply_protection_without_network_confirms_directly() -> void:
	_inventory.on_item_add_confirmed(SWORD, 1, P1)
	_inventory.on_item_add_confirmed(SCROLL_PVE, 1, P1)
	_protection.request_apply_protection(SCROLL_PVE, SWORD, P1)
	assert_true(_protection.is_protected_from(P1, SWORD, "pve"), "Ohne Network-Bridge muss request_apply_protection() sofort anwenden")

func test_request_apply_protection_as_client_routes_via_network_not_local() -> void:
	var bridge: MockBridgeAsClient = add_child_autofree(MockBridgeAsClient.new())
	_inventory.on_item_add_confirmed(SWORD, 1, P1)
	_inventory.on_item_add_confirmed(SCROLL_PVE, 1, P1)
	_protection.inject_network_bridge(bridge)

	_protection.request_apply_protection(SCROLL_PVE, SWORD, P1)

	assert_eq(bridge.apply_calls, [[SCROLL_PVE, SWORD, P1]])
	assert_false(_protection.is_protected_from(P1, SWORD, "pve"), "Auf dem Client darf der Schutz nicht direkt angewendet werden")
	assert_true(_inventory.has_item(SCROLL_PVE, P1, 1), "Auf dem Client darf das Scroll nicht verbraucht werden")
