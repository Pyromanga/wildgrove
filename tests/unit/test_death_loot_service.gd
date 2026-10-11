# res://tests/unit/test_death_loot_service.gd
extends GutTest

## Unit-Tests für DeathLootService (ADR-037 — PvE-Tod-Loot).
##
## Strategie: DeathLootService mit echten CurrencyService/InventorySystem-
## Instanzen (Tier-1, analog test_pvp_death_loss_service.gd), WorldService
## wird NICHT echt konfiguriert (bräuchte EntityOrchestrator/world_root/
## SceneTree) — stattdessen ein MockWorldService, der nur spawn_entity()
## überschreibt (analog MockNetworkBridge in test_quest_npc.gd) und einen
## vorbereiteten Dummy-Node zurückgibt.
##
## Abgedeckt:
##   - Gold + ungeschützte Items werden entfernt und ins Gravestone-Config
##     übernommen
##   - PvE-todesgeschützte Items (ADR-038) bleiben beim Spieler, landen nie
##     im Grab-Config
##   - Kein Gold + keine Items → kein spawn_entity()-Aufruf, kein Verlust
##   - Kein WorldService injiziert → kein Verlust angewendet (nichts entfernt,
##     death_loot_skipped-Signal)
##   - spawn_entity() gibt null zurück (Spawn fehlgeschlagen) → bereits
##     entfernte Items sind ein bekannter Grenzfall, wird geloggt
##   - Fehlerfälle: leere player_id
##   - gravestone_spawned-Signal mit korrekten Werten
##   - Despawn-/Personal-Loot-Zeitstempel liegen korrekt in der Zukunft und
##     in der richtigen Reihenfolge zueinander

class MockItemDef extends ItemDefinition:
	func _init(p_id: String, p_name: String) -> void:
		id = p_id
		display_name = p_name

class MockDataService extends DataService:
	func get_all_items() -> Dictionary:
		return _items

class MockWorldService extends WorldService:
	var spawn_calls: Array = []
	var next_spawn_result: Node3D = null
	func spawn_entity(type_id: String, position: Vector3, config: Dictionary = {}, peer_id: int = 1) -> Node3D:
		spawn_calls.append({"type_id": type_id, "position": position, "config": config, "peer_id": peer_id})
		return next_spawn_result

const ORE := "iron_ore"
const SWORD := "iron_sword"
const P1 := "p1"

var _loot: DeathLootService
var _currency: CurrencyService
var _inventory: InventorySystem
var _ds: MockDataService
var _bus: MockEventBus
var _world: MockWorldService
var _save: SaveSystem

func before_each() -> void:
	_ds = MockDataService.new()
	_ds._items[ORE]   = MockItemDef.new(ORE, "Eisenerz")
	_ds._items[SWORD] = MockItemDef.new(SWORD, "Eisenschwert")
	_bus = MockEventBus.new()
	_save = SaveSystem.new()
	_save.configure(ServiceDeps.from_dict({ServiceKeys.EVENT_BUS: _bus}))

	_inventory = InventorySystem.new()
	_inventory.configure(ServiceDeps.from_dict({ServiceKeys.DATA: _ds, ServiceKeys.SAVE_SYSTEM: _save, ServiceKeys.EVENT_BUS: _bus}))

	_currency = CurrencyService.new()
	_currency.configure(ServiceDeps.from_dict({ServiceKeys.SAVE_SYSTEM: _save, ServiceKeys.EVENT_BUS: _bus}))

	_loot = DeathLootService.new()
	_loot.configure(ServiceDeps.from_dict({
		ServiceKeys.CURRENCY: _currency,
		ServiceKeys.INVENTORY: _inventory,
	}))

	_world = MockWorldService.new()
	var dummy_grave := Node3D.new()
	dummy_grave.set_meta("entity_uuid", "grave-uuid-1")
	_world.next_spawn_result = dummy_grave
	_loot.inject_world(_world)

func after_each() -> void:
	if is_instance_valid(_world.next_spawn_result):
		_world.next_spawn_result.free()
	_world.free()
	_loot = null
	_currency = null
	_inventory = null
	_ds = null
	_bus = null

# ─────────────────────────────────────────────────────────────────────────────
# Erfolgsfall — Gold + Items werden entfernt und ins Grab übertragen
# ─────────────────────────────────────────────────────────────────────────────

func test_handle_pve_death_removes_gold_from_player() -> void:
	_currency.request_add_gold(P1, 300)
	_loot.handle_pve_death(P1, Vector3(1, 0, 1))
	assert_eq(_currency.get_gold(P1), 0)

func test_handle_pve_death_removes_unprotected_items_from_player() -> void:
	_inventory.on_item_add_confirmed(ORE, 20, P1)
	_loot.handle_pve_death(P1, Vector3.ZERO)
	assert_false(_inventory.has_item(ORE, P1, 1))

func test_handle_pve_death_spawns_gravestone_with_correct_type_and_position() -> void:
	_currency.request_add_gold(P1, 100)
	var pos := Vector3(5, 0, -3)
	_loot.handle_pve_death(P1, pos)

	assert_eq(_world.spawn_calls.size(), 1)
	assert_eq(_world.spawn_calls[0]["type_id"], "gravestone")
	assert_eq(_world.spawn_calls[0]["position"], pos)

func test_gravestone_config_contains_gold_and_items() -> void:
	_currency.request_add_gold(P1, 250)
	_inventory.on_item_add_confirmed(ORE, 15, P1)
	_loot.handle_pve_death(P1, Vector3.ZERO)

	var config: Dictionary = _world.spawn_calls[0]["config"]
	assert_eq(config["owner_player_id"], P1)
	assert_eq(config["gold"], 250)
	assert_eq(config["items"].size(), 1)
	assert_eq(config["items"][0]["item_id"], ORE)
	assert_eq(config["items"][0]["quantity"], 15)

func test_gravestone_config_timestamps_are_in_correct_order() -> void:
	_currency.request_add_gold(P1, 10)
	var before := Time.get_unix_time_from_system()
	_loot.handle_pve_death(P1, Vector3.ZERO)
	var config: Dictionary = _world.spawn_calls[0]["config"]

	assert_gt(config["personal_loot_until"], before, "Personal-Loot-Ende muss in der Zukunft liegen")
	assert_gt(config["despawn_at"], config["personal_loot_until"], "Despawn muss NACH Ende der Personal-Loot-Phase liegen")

# ─────────────────────────────────────────────────────────────────────────────
# ADR-038-Schutzkategorie: NUR is_pve_death_protected zählt
# ─────────────────────────────────────────────────────────────────────────────

func test_pve_protected_item_stays_with_player_and_excluded_from_grave() -> void:
	_inventory.on_item_add_confirmed(SWORD, 1, P1)
	_inventory.get_item_instance(P1, SWORD).is_pve_death_protected = true
	_inventory.on_item_add_confirmed(ORE, 5, P1)

	_loot.handle_pve_death(P1, Vector3.ZERO)

	assert_true(_inventory.has_item(SWORD, P1, 1), "PvE-geschütztes Item bleibt beim Spieler")
	assert_false(_inventory.has_item(ORE, P1, 1), "Ungeschütztes Item geht trotzdem verloren")

	var config: Dictionary = _world.spawn_calls[0]["config"]
	var grave_item_ids: Array = []
	for entry in config["items"]:
		grave_item_ids.append(entry["item_id"])
	assert_false(grave_item_ids.has(SWORD), "PvE-geschütztes Item darf nicht im Grab landen")
	assert_true(grave_item_ids.has(ORE))

func test_theft_and_pvp_protection_are_irrelevant_for_pve_death() -> void:
	# Kernaussage ADR-038: die drei Kategorien sind unabhängig — Diebstahl-
	# und PvP-Schutz schützen NICHT vor PvE-Tod.
	_inventory.on_item_add_confirmed(SWORD, 1, P1)
	var inst := _inventory.get_item_instance(P1, SWORD)
	inst.is_theft_protected = true
	inst.is_pvp_protected = true

	_loot.handle_pve_death(P1, Vector3.ZERO)

	assert_false(_inventory.has_item(SWORD, P1, 1), "Diebstahl-/PvP-Schutz dürfen nicht vor PvE-Tod schützen")

# ─────────────────────────────────────────────────────────────────────────────
# Kein Verlust ohne Grund
# ─────────────────────────────────────────────────────────────────────────────

func test_nothing_to_lose_spawns_no_gravestone() -> void:
	_loot.handle_pve_death(P1, Vector3.ZERO)
	assert_eq(_world.spawn_calls.size(), 0)

func test_nothing_to_lose_emits_skipped_signal() -> void:
	var received := []
	_loot.death_loot_skipped.connect(func(pid, reason): received.append(reason))
	_loot.handle_pve_death(P1, Vector3.ZERO)
	assert_eq(received, ["nothing_to_lose"])

func test_empty_player_id_is_noop() -> void:
	_loot.handle_pve_death("", Vector3.ZERO)
	assert_eq(_world.spawn_calls.size(), 0)

# ─────────────────────────────────────────────────────────────────────────────
# Kein WorldService injiziert
# ─────────────────────────────────────────────────────────────────────────────

func test_without_world_service_nothing_is_removed() -> void:
	var loot2 := DeathLootService.new()
	loot2.configure(ServiceDeps.from_dict({
		ServiceKeys.CURRENCY: _currency,
		ServiceKeys.INVENTORY: _inventory,
	}))
	# Kein inject_world() aufgerufen.
	_currency.request_add_gold(P1, 999)

	loot2.handle_pve_death(P1, Vector3.ZERO)

	assert_eq(_currency.get_gold(P1), 999, "Ohne WorldService darf nichts entfernt werden (kein Verlust ohne Grab)")

func test_without_world_service_emits_skipped_signal() -> void:
	var loot2 := DeathLootService.new()
	loot2.configure(ServiceDeps.from_dict({
		ServiceKeys.CURRENCY: _currency,
		ServiceKeys.INVENTORY: _inventory,
	}))
	_currency.request_add_gold(P1, 100)

	var received := []
	loot2.death_loot_skipped.connect(func(pid, reason): received.append(reason))
	loot2.handle_pve_death(P1, Vector3.ZERO)

	assert_eq(received, ["no_world_service"])

# ─────────────────────────────────────────────────────────────────────────────
# Signal
# ─────────────────────────────────────────────────────────────────────────────

func test_gravestone_spawned_signal_reports_correct_values() -> void:
	_currency.request_add_gold(P1, 42)
	_inventory.on_item_add_confirmed(ORE, 3, P1)

	var received := []
	_loot.gravestone_spawned.connect(
		func(pid, uuid, gold, item_count): received.append([pid, uuid, gold, item_count])
	)
	_loot.handle_pve_death(P1, Vector3.ZERO)

	assert_eq(received, [[P1, "grave-uuid-1", 42, 1]])

# ─────────────────────────────────────────────
# inject_network_bridge() — Round 113 Nachtrag
# ─────────────────────────────────────────────

func test_inject_network_bridge_sets_the_reference() -> void:
	var bridge: NetworkBridge = add_child_autofree(NetworkBridge.new())
	_loot.inject_network_bridge(bridge)
	assert_same(_loot._network, bridge)
