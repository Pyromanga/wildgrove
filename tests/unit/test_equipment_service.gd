## tests/unit/test_equipment_service.gd
## Unit-Tests für EquipmentService.
##
## Abdeckung:
##   - equip() / unequip() / get_equipped() / is_equipped()
##   - StatModifier-Anbindung: damage_bonus via StatModifierService
##   - PARALLELE BUFFS: zwei Slots → zwei unabhängige Modifier
##   - Slot-Exklusivität: erneutes equip() auf denselben Slot ersetzt nur diesen Modifier
##   - unequip() entfernt Modifier + Visual symmetrisch
##   - on_cleanup() räumt alle "equipment_"-Modifier in einem Rutsch ab
##   - get_equipped_weapon() liefert null für Nicht-Waffen-Items
##   - Multi-Tenancy: player_id-Isolation, clear_player()
##   - ISaveProvider: get_save_key() / get_save_data() / load_data() + round-trip
##
## ADR-029 Round 66: player_id ist jetzt String (player_uuid), Pflichtparameter
## ohne Default auf allen öffentlichen Methoden — kein "Player 1" mehr implizit.
## `equip()`/`get_equipped_weapon()` haben zusätzlich player_id VOR ihrem
## jeweiligen optionalen Parameter (visuals/slot) — GDScript-Zwang, siehe
## EquipmentService.gd-Klassenkommentar.
##
## Round 69: StatModifierService ist jetzt ebenfalls auf player_id: String
## migriert — _apply_stat_bonus() reicht player_id direkt durch, keine
## peer_id-Übersetzung mehr für die StatModifier-Assertions unten nötig.
## NetworkBridge + SessionManager bleiben trotzdem gewired (feste peer_id ↔
## player_id-Zuordnungen: "p1" → 1, "p2" → 2, "p7" → 7, "p10" → 10,
## "p11" → 11) — weiterhin gebraucht für den verbleibenden unmigrierten
## Nachbarn WorldService.get_player_visuals() (_resolve_peer_id() in
## on_equip_confirmed(), siehe test_equipment_service_r4.gd) und für Signal-/
## Save-Tests, die realistisches Wiring erwarten.

extends GutTest

## Minimal DataService-Stub: EquipmentService.load_data() braucht DataService.get_item()
## um item_id → ItemDefinition aufzulösen (siehe EquipmentService.gd). Ohne diese Dep
## bleibt Equipment nach einem Reload leer (dokumentiertes, korrektes Verhalten).
class MockDataService extends DataService:
	pass  ## get_item()/_items sind bereits in DataService — Test befüllt _items direkt.

var _equipment: EquipmentService
var _stat_mods: StatModifierService
## Minimal SaveSystem stand-in: records registered providers and returns preset state.
## Muss "extends SaveSystem" sein, da Produktionscode per DI-Konvention hart auf
## SaveSystem castet (deps.require(...) as SaveSystem) — siehe ISaveProvider.gd.
class MockSaveSystem extends SaveSystem:
	var providers: Array = []
	var _preset_state: Dictionary = {}

	func register_save_provider(p: Object) -> void:
		providers.append(p)

	func get_state_for(key: String) -> Dictionary:
		return _preset_state.get(key, {})

	func set_preset(key: String, value: Dictionary) -> void:
		_preset_state[key] = value

var _save_sys: MockSaveSystem
var _bus: MockEventBus
var _session: SessionManager
var _bridge: NetworkBridge

func before_each() -> void:
	_stat_mods = StatModifierService.new()
	_save_sys = MockSaveSystem.new()
	_bus = MockEventBus.new()

	_session = SessionManager.new()
	_session.register_player_slot(1, "p1")
	_session.register_player_slot(2, "p2")
	_session.register_player_slot(7, "p7")
	_session.register_player_slot(10, "p10")
	_session.register_player_slot(11, "p11")
	add_child_autofree(_session)

	_bridge = NetworkBridge.new()
	_bridge.configure(ServiceDeps.from_dict({
		ServiceKeys.EVENT_BUS: _bus,
		ServiceKeys.SESSION_MANAGER: _session,
	}))
	add_child_autofree(_bridge)

	_equipment = EquipmentService.new()
	_equipment.configure(ServiceDeps.from_dict({
		"stat_modifiers": _stat_mods,
		"savesystem": _save_sys,
		"network_bridge": _bridge,
	}))

func after_each() -> void:
	_equipment.on_cleanup()
	_stat_mods.on_cleanup()
	_equipment = null
	_stat_mods = null
	_save_sys = null
	_bus = null
	_session = null
	_bridge = null

func _make_weapon(id: String, dmg_bonus: float) -> WeaponDefinition:
	var w := WeaponDefinition.new()
	w.id = id
	w.display_name = id
	w.damage_bonus = dmg_bonus
	return w

# ─────────────────────────────────────────────
# equip / unequip / Accessors
# ─────────────────────────────────────────────

func test_equip_stores_item_in_slot() -> void:
	var sword := _make_weapon("iron_sword", 5.0)
	assert_true(_equipment.equip("weapon", sword, "p1"))
	assert_eq(_equipment.get_equipped("weapon", "p1"), sword)
	assert_true(_equipment.is_equipped("weapon", "p1"))

func test_equip_rejects_empty_slot() -> void:
	var sword := _make_weapon("iron_sword", 5.0)
	assert_false(_equipment.equip("", sword, "p1"))

func test_equip_rejects_invalid_item() -> void:
	assert_false(_equipment.equip("weapon", null, "p1"))

func test_unequip_clears_slot() -> void:
	var sword := _make_weapon("iron_sword", 5.0)
	_equipment.equip("weapon", sword, "p1")
	assert_true(_equipment.unequip("weapon", "p1"))
	assert_false(_equipment.is_equipped("weapon", "p1"))
	assert_null(_equipment.get_equipped("weapon", "p1"))

func test_unequip_empty_slot_returns_false() -> void:
	assert_false(_equipment.unequip("weapon", "p1"))

func test_get_equipped_weapon_returns_null_for_non_weapon_item() -> void:
	var generic_item := ItemDefinition.new()
	generic_item.id = "raw_log"
	_equipment.equip("offhand", generic_item, "p1")
	assert_null(_equipment.get_equipped_weapon("p1", "offhand"))

# ─────────────────────────────────────────────
# StatModifier-Anbindung
# ─────────────────────────────────────────────

func test_equip_applies_damage_bonus_as_stat_modifier() -> void:
	var sword := _make_weapon("iron_sword", 5.0)
	_equipment.equip("weapon", sword, "p1")
	assert_true(_stat_mods.has_modifier("equipment_weapon", "p1"))
	assert_eq(_stat_mods.get_effective_stat("damage_bonus", 10.0, "p1"), 15.0)

func test_unequip_removes_stat_modifier() -> void:
	var sword := _make_weapon("iron_sword", 5.0)
	_equipment.equip("weapon", sword, "p1")
	_equipment.unequip("weapon", "p1")
	assert_false(_stat_mods.has_modifier("equipment_weapon", "p1"))
	assert_eq(_stat_mods.get_effective_stat("damage_bonus", 10.0, "p1"), 10.0)

func test_equip_zero_damage_bonus_adds_no_modifier() -> void:
	var dagger := _make_weapon("starter_dagger", 0.0)
	_equipment.equip("weapon", dagger, "p1")
	assert_false(_stat_mods.has_modifier("equipment_weapon", "p1"))

# ─────────────────────────────────────────────
# Parallele Buffs (Kernanforderung)
# ─────────────────────────────────────────────

func test_two_slots_apply_independent_parallel_modifiers() -> void:
	var sword := _make_weapon("iron_sword", 5.0)
	var ring  := _make_weapon("power_ring", 3.0)

	_equipment.equip("weapon", sword, "p1")
	_equipment.equip("offhand", ring, "p1")

	assert_true(_stat_mods.has_modifier("equipment_weapon", "p1"))
	assert_true(_stat_mods.has_modifier("equipment_offhand", "p1"))
	assert_eq(_stat_mods.get_effective_stat("damage_bonus", 10.0, "p1"), 18.0)

func test_unequipping_one_slot_leaves_other_slot_active() -> void:
	var sword := _make_weapon("iron_sword", 5.0)
	var ring  := _make_weapon("power_ring", 3.0)
	_equipment.equip("weapon", sword, "p1")
	_equipment.equip("offhand", ring, "p1")

	_equipment.unequip("weapon", "p1")

	assert_false(_stat_mods.has_modifier("equipment_weapon", "p1"))
	assert_true(_stat_mods.has_modifier("equipment_offhand", "p1"))
	assert_eq(_stat_mods.get_effective_stat("damage_bonus", 10.0, "p1"), 13.0)

func test_reequipping_same_slot_replaces_only_that_modifier() -> void:
	var sword        := _make_weapon("iron_sword", 5.0)
	var better_sword := _make_weapon("steel_sword", 8.0)
	var ring         := _make_weapon("power_ring", 3.0)

	_equipment.equip("weapon", sword, "p1")
	_equipment.equip("offhand", ring, "p1")
	_equipment.equip("weapon", better_sword, "p1")

	assert_eq(_equipment.get_equipped("weapon", "p1"), better_sword)
	assert_true(_stat_mods.has_modifier("equipment_offhand", "p1"), "offhand-Slot darf vom weapon-Re-Equip nicht betroffen sein.")
	assert_eq(_stat_mods.get_effective_stat("damage_bonus", 10.0, "p1"), 21.0)  # 10 + 8 + 3

# ─────────────────────────────────────────────
# Cleanup
# ─────────────────────────────────────────────

func test_on_cleanup_removes_all_equipment_modifiers() -> void:
	_equipment.equip("weapon", _make_weapon("iron_sword", 5.0), "p1")
	_equipment.equip("offhand", _make_weapon("power_ring", 3.0), "p1")

	_equipment.on_cleanup()

	assert_false(_stat_mods.has_modifier("equipment_weapon", "p1"))
	assert_false(_stat_mods.has_modifier("equipment_offhand", "p1"))
	assert_false(_equipment.is_equipped("weapon", "p1"))
	assert_false(_equipment.is_equipped("offhand", "p1"))

# ─────────────────────────────────────────────
# Signal
# ─────────────────────────────────────────────

func test_equip_emits_equipment_changed_signal() -> void:
	watch_signals(_equipment)
	var sword := _make_weapon("iron_sword", 5.0)
	_equipment.equip("weapon", sword, "p1")
	assert_signal_emitted_with_parameters(_equipment, "equipment_changed", ["weapon", sword, "p1"])

func test_unequip_emits_equipment_changed_with_null() -> void:
	var sword := _make_weapon("iron_sword", 5.0)
	_equipment.equip("weapon", sword, "p1")
	watch_signals(_equipment)
	_equipment.unequip("weapon", "p1")
	assert_signal_emitted_with_parameters(_equipment, "equipment_changed", ["weapon", null, "p1"])

func test_equip_emits_equipment_changed_with_correct_player_id() -> void:
	watch_signals(_equipment)
	var axe := _make_weapon("iron_axe", 8.0)
	_equipment.equip("weapon", axe, "p7")
	assert_signal_emitted_with_parameters(_equipment, "equipment_changed", ["weapon", axe, "p7"])

# ─────────────────────────────────────────────
# Multi-Tenancy (Prio 3)
# ─────────────────────────────────────────────

func test_different_player_ids_have_isolated_slots() -> void:
	var sword := _make_weapon("iron_sword", 5.0)
	var axe   := _make_weapon("iron_axe", 8.0)

	_equipment.equip("weapon", sword, "p1")
	_equipment.equip("weapon", axe, "p2")

	assert_eq(_equipment.get_equipped("weapon", "p1"), sword, "Player 1 muss sein eigenes Item haben.")
	assert_eq(_equipment.get_equipped("weapon", "p2"), axe, "Player 2 muss sein eigenes Item haben.")

func test_stat_modifiers_are_isolated_per_player() -> void:
	_equipment.equip("weapon", _make_weapon("sword_p1", 5.0), "p1")
	_equipment.equip("weapon", _make_weapon("sword_p2", 20.0), "p2")

	assert_eq(_stat_mods.get_effective_stat("damage_bonus", 10.0, "p1"), 15.0, "Player 1: 10 + 5")
	assert_eq(_stat_mods.get_effective_stat("damage_bonus", 10.0, "p2"), 30.0, "Player 2: 10 + 20")

func test_unequip_only_affects_target_player() -> void:
	_equipment.equip("weapon", _make_weapon("sword", 5.0), "p1")
	_equipment.equip("weapon", _make_weapon("sword", 5.0), "p2")

	_equipment.unequip("weapon", "p1")

	assert_false(_equipment.is_equipped("weapon", "p1"))
	assert_true(_equipment.is_equipped("weapon", "p2"), "Player 2 muss unberührt bleiben.")

func test_clear_player_removes_all_slots_and_modifiers() -> void:
	_equipment.equip("weapon", _make_weapon("sword", 5.0), "p10")
	_equipment.equip("offhand", _make_weapon("ring", 2.0), "p10")
	_equipment.equip("weapon", _make_weapon("sword", 5.0), "p11")

	_equipment.clear_player("p10")

	assert_false(_equipment.is_equipped("weapon", "p10"))
	assert_false(_equipment.is_equipped("offhand", "p10"))
	assert_false(_stat_mods.has_modifier("equipment_weapon", "p10"))
	assert_true(_equipment.is_equipped("weapon", "p11"), "Player 11 muss unberührt bleiben.")

func test_player_ids_are_fully_isolated_buckets() -> void:
	## ADR-029 Round 66: ersetzt den alten "Default-player_id-ist-1"-Test — es
	## gibt keinen Default mehr, jeder Aufrufer muss player_id explizit angeben.
	## Testet stattdessen weiterhin die Kern-Multi-Tenancy-Garantie: zwei
	## Spieler-Buckets sehen sich gegenseitig nie.
	_equipment.equip("weapon", _make_weapon("sword", 3.0), "p1")
	assert_true(_equipment.is_equipped("weapon", "p1"))
	assert_false(_equipment.is_equipped("weapon", "p2"), "Player 2 darf nichts sehen.")

# ─────────────────────────────────────────────
# ISaveProvider (Prio 3)
# ─────────────────────────────────────────────

func test_save_data_includes_equipped_item_id() -> void:
	_equipment.equip("weapon", _make_weapon("iron_sword", 5.0), "p1")

	var data := _equipment.get_save_data()

	assert_true(data.has("p1"), "Player 'p1' muss im Save-Blob sein.")
	assert_eq(data["p1"]["weapon"], "iron_sword")

func test_save_data_is_empty_when_nothing_equipped() -> void:
	var data := _equipment.get_save_data()
	assert_eq(data, {})

func test_save_key_returns_equipment() -> void:
	assert_eq(_equipment.get_save_key(), "equipment")

func test_save_data_null_slot_when_unequipped_after_equip() -> void:
	## Unequip löscht den Slot aus dem Dict — kein null-Eintrag im Save.
	_equipment.equip("weapon", _make_weapon("iron_sword", 5.0), "p1")
	_equipment.unequip("weapon", "p1")
	var data := _equipment.get_save_data()
	# Player "p1" wird angelegt aber hat leeren Slot-Dict → "p1" hat kein "weapon"
	if data.has("p1"):
		assert_false(data["p1"].has("weapon"), "Entfernte Slots dürfen nicht im Save sein.")

# ─────────────────────────────────────────────
# Save/Load Round-Trip (Prio 3 — war fehlend)
# ─────────────────────────────────────────────

func test_register_save_provider_called_on_configure() -> void:
	assert_eq(_save_sys.providers.size(), 1, "EquipmentService muss sich beim SaveSystem registrieren.")
	assert_eq(_save_sys.providers[0], _equipment)

func test_get_save_key_matches_load_key() -> void:
	## SaveSystem nutzt get_save_key() als Lookup-Key für get_state_for() — beide müssen übereinstimmen.
	assert_eq(_equipment.get_save_key(), "equipment")

func test_round_trip_equip_save_reload_restores_item() -> void:
	## Equip → serialize → new service with preset state → verify loaded.
	var sword := _make_weapon("iron_sword", 5.0)
	_equipment.equip("weapon", sword, "p1")

	var saved := _equipment.get_save_data()

	# Simulate a new session: new service, SaveSystem returns saved state.
	# Bewusst OHNE NetworkBridge — load_data()/_apply_stat_bonus() dürfen auch
	# ohne Bridge nicht crashen (StatModifier-Bonus wird dann übersprungen,
	# siehe EquipmentService._resolve_peer_id()), nur die reine
	# Reload-Fähigkeit wird hier geprüft.
	var save_sys2 := MockSaveSystem.new()
	save_sys2.set_preset("equipment", saved)
	var stat_mods2 := StatModifierService.new()
	var data2 := MockDataService.new()
	data2._items[sword.id] = sword
	var equipment2 := EquipmentService.new()
	equipment2.configure(ServiceDeps.from_dict({
		"stat_modifiers": stat_mods2,
		"savesystem": save_sys2,
		"data": data2,
	}))

	assert_true(equipment2.is_equipped("weapon", "p1"), "Nach Reload muss Slot 'weapon' belegt sein.")
	var loaded_item := equipment2.get_equipped("weapon", "p1")
	assert_not_null(loaded_item, "Geladenes Item darf nicht null sein.")
	assert_eq(loaded_item.id, "iron_sword", "Item-ID muss nach Reload übereinstimmen.")

	equipment2.on_cleanup()
	stat_mods2.on_cleanup()

func test_round_trip_empty_save_produces_empty_equipment() -> void:
	## A fresh save (no equipment key) must load as empty, not error.
	var save_sys2 := MockSaveSystem.new()
	var stat_mods2 := StatModifierService.new()
	var equipment2 := EquipmentService.new()
	equipment2.configure(ServiceDeps.from_dict({
		"stat_modifiers": stat_mods2,
		"savesystem": save_sys2,
	}))

	assert_false(equipment2.is_equipped("weapon", "p1"), "Leerer Save → kein Equipment.")
	equipment2.on_cleanup()
	stat_mods2.on_cleanup()

# ─────────────────────────────────────────────
# Netzwerk-Routing — inject_network_bridge()/request_equip()/request_unequip()
# (Round 113 Nachtrag, siehe method_reference_coverage.py-Fund)
# ─────────────────────────────────────────────

class MockBridgeAsClient extends NetworkBridge:
	var equip_calls: Array = []
	var unequip_calls: Array = []
	func has_peer() -> bool:
		return true
	func is_server() -> bool:
		return false
	func send_equip_item(slot: String, item_id: String, player_id: String) -> void:
		equip_calls.append([slot, item_id, player_id])
	func send_unequip_item(slot: String, player_id: String) -> void:
		unequip_calls.append([slot, player_id])

func test_inject_network_bridge_sets_the_reference() -> void:
	var fresh_bridge: NetworkBridge = add_child_autofree(NetworkBridge.new())
	_equipment.inject_network_bridge(fresh_bridge)
	assert_same(_equipment._network, fresh_bridge)

func test_inject_network_bridge_connects_economy_state_received() -> void:
	var fresh_bridge: NetworkBridge = add_child_autofree(NetworkBridge.new())
	assert_eq(fresh_bridge.economy_state_received.get_connections().size(), 0)
	_equipment.inject_network_bridge(fresh_bridge)
	assert_eq(fresh_bridge.economy_state_received.get_connections().size(), 1)

func test_request_equip_without_network_confirms_directly() -> void:
	var sword := _make_weapon("iron_sword", 5.0)
	var data := MockDataService.new()
	data._items[sword.id] = sword
	var eq := EquipmentService.new()
	eq.configure(ServiceDeps.from_dict({
		"stat_modifiers": _stat_mods,
		"savesystem": MockSaveSystem.new(),
		"data": data,
	}))
	# Kein Network konfiguriert -> _network bleibt null -> synchroner Pfad.
	eq.request_equip("weapon", sword.id, "p1")
	assert_true(eq.is_equipped("weapon", "p1"), "Ohne Network-Bridge muss request_equip() sofort ausrüsten")
	eq.on_cleanup()

func test_request_equip_as_client_routes_via_network_not_local() -> void:
	var bridge: MockBridgeAsClient = add_child_autofree(MockBridgeAsClient.new())
	var sword := _make_weapon("iron_sword", 5.0)
	var data := MockDataService.new()
	data._items[sword.id] = sword
	var eq := EquipmentService.new()
	eq.configure(ServiceDeps.from_dict({
		"stat_modifiers": _stat_mods,
		"savesystem": MockSaveSystem.new(),
		"data": data,
	}))
	eq.inject_network_bridge(bridge)

	eq.request_equip("weapon", sword.id, "p1")

	assert_eq(bridge.equip_calls, [["weapon", sword.id, "p1"]])
	assert_false(eq.is_equipped("weapon", "p1"), "Auf dem Client darf nicht direkt ausgerüstet werden")
	eq.on_cleanup()

func test_request_unequip_without_network_confirms_directly() -> void:
	var sword := _make_weapon("iron_sword", 5.0)
	_equipment.equip("weapon", sword, "p1")

	_equipment.request_unequip("weapon", "p1")

	assert_false(_equipment.is_equipped("weapon", "p1"), "Ohne Network-Bridge muss request_unequip() sofort ausziehen")

func test_request_unequip_as_client_routes_via_network_not_local() -> void:
	var bridge: MockBridgeAsClient = add_child_autofree(MockBridgeAsClient.new())
	var sword := _make_weapon("iron_sword", 5.0)
	_equipment.equip("weapon", sword, "p1")
	_equipment.inject_network_bridge(bridge)

	_equipment.request_unequip("weapon", "p1")

	assert_eq(bridge.unequip_calls, [["weapon", "p1"]])
	assert_true(_equipment.is_equipped("weapon", "p1"), "Auf dem Client darf nicht direkt ausgezogen werden")

func test_on_unequip_confirmed_syncs_null_item_id_to_network() -> void:
	var sword := _make_weapon("iron_sword", 5.0)
	_equipment.equip("weapon", sword, "p1")

	_equipment.on_unequip_confirmed("weapon", "p1")

	assert_false(_equipment.is_equipped("weapon", "p1"))

# ─────────────────────────────────────────────
# Debug-API
# ─────────────────────────────────────────────

func test_get_debug_report_lists_equipped_items() -> void:
	var sword := _make_weapon("iron_sword", 5.0)
	_equipment.equip("weapon", sword, "p1")
	var report := _equipment.get_debug_report("p1")
	assert_eq(report.size(), 1)
	assert_true(report[0].contains("weapon"))
	assert_true(report[0].contains("iron_sword"))

func test_get_debug_report_empty_for_player_without_equipment() -> void:
	assert_eq(_equipment.get_debug_report("nobody"), [])
