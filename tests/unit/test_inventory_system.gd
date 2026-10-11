# res://tests/unit/test_inventory_system.gd
extends GutTest

## Unit-Tests für InventorySystem (E-02).
##
## Strategie: InventorySystem direkt instanziieren mit einer
## Minimal-Mock-Item-Registry. configure() erhält nur einen minimalen DataService-Stub.
## Kein SaveSystem, kein NetworkBridge — Tier-1-Pfad (direkte Mutations).
##
## ADR-029 Plan-Schritt 4 (Round 63): player_id ist jetzt player_uuid (String,
## Pflichtparameter, kein Default mehr) statt peer_id (int, Default 1). P1/P2
## sind hier reine opake Test-Bucket-Keys, keine echten UUIDs — das genügt,
## InventorySystem behandelt player_id ohnehin nur als Dictionary-Key.
## has_item()/remove_item()/request_add_item() haben dabei auch ihre Parameter-
## Reihenfolge geändert: player_id steht jetzt vor dem optionalen quantity
## (GDScript erlaubt keinen Pflichtparameter nach einem Default-Parameter) —
## siehe InventorySystem.gd Klassenkommentar.
##
## Abgedeckt:
##   - on_item_add_confirmed(): einfaches Hinzufügen, Stapeln, Stack-Cap
##   - remove_item(): korrekte Reduktion, Fehler bei zu wenig
##   - has_item(): korrekte Prüfung
##   - request_add_item(): Slot-Limit, Gewichtslimit, unbekanntes Item
##   - Gewichtstracking nach Add / Remove
##   - Multi-Tenanz: zwei player_ids unabhängig
##   - get_save_key() / get_save_data() Serialisierungs-Snapshot
##   - Save-Round-Trip: save_data → _restore_from_save → gleicher State

# ─────────────────────────────────────────────────────────────────────────────
# Minimal-Mock: ItemDefinition-ähnliches Objekt
# ─────────────────────────────────────────────────────────────────────────────

class MockItemDef extends ItemDefinition:
	var weight: float = 1.0

	func _init(p_name: String, p_max_stack: int = 99, p_weight: float = 1.0) -> void:
		display_name = p_name
		max_stack    = p_max_stack
		weight       = p_weight

# ─────────────────────────────────────────────────────────────────────────────
# Minimal-Mock: DataService-Stub
# ─────────────────────────────────────────────────────────────────────────────

class MockDataService extends DataService:
	func get_all_items() -> Dictionary:
		return _items

# ─────────────────────────────────────────────────────────────────────────────
# Test-Setup
# ─────────────────────────────────────────────────────────────────────────────

var _svc:   InventorySystem
var _ds:    MockDataService
var _bus:   MockEventBus
var _item_a: MockItemDef
var _item_b: MockItemDef

const ITEM_A := "iron_ore"
const ITEM_B := "log_oak"
const P1 := "p1"
const P2 := "p2"

func before_each() -> void:
	_item_a = MockItemDef.new("Iron Ore", 50, 2.0)
	_item_b = MockItemDef.new("Oak Log",  20, 3.0)
	_ds     = MockDataService.new()
	_ds._items[ITEM_A] = _item_a
	_ds._items[ITEM_B] = _item_b
	_bus = MockEventBus.new()

	_svc = InventorySystem.new()
	# configure() ohne SaveSystem → kein Restore, kein Provider-Register
	_svc.configure(ServiceDeps.from_dict({
		ServiceKeys.DATA:      _ds,
		ServiceKeys.EVENT_BUS: _bus,
	}))

func after_each() -> void:
	_svc.on_cleanup()
	_svc = null

# ─────────────────────────────────────────────────────────────────────────────
# on_item_add_confirmed — Basisfälle
# ─────────────────────────────────────────────────────────────────────────────

func test_add_item_increases_quantity() -> void:
	_svc.on_item_add_confirmed(ITEM_A, 5, P1)
	assert_true(_svc.has_item(ITEM_A, P1, 5), "5x iron_ore müssen vorhanden sein")

func test_add_item_twice_stacks() -> void:
	_svc.on_item_add_confirmed(ITEM_A, 3, P1)
	_svc.on_item_add_confirmed(ITEM_A, 4, P1)
	assert_true(_svc.has_item(ITEM_A, P1, 7), "Gestapelt: 7x erwartet")

func test_add_item_caps_at_max_stack() -> void:
	# max_stack = 50
	_svc.on_item_add_confirmed(ITEM_A, 48, P1)
	_svc.on_item_add_confirmed(ITEM_A, 10, P1)  # würde auf 58 gehen → cap bei 50
	var all := _svc.get_all_items(P1)
	var found := false
	for entry in all:
		if entry["id"] == ITEM_A:
			assert_lte(entry["quantity"], 50, "Stack darf max_stack (50) nicht überschreiten")
			found = true
	assert_true(found, "iron_ore muss in get_all_items() erscheinen")

func test_add_unknown_item_is_silent() -> void:
	_svc.on_item_add_confirmed("nonexistent_item", 1, P1)
	assert_false(_svc.has_item("nonexistent_item", P1), "Unbekanntes Item darf nicht anlegen")

# ─────────────────────────────────────────────────────────────────────────────
# remove_item
# ─────────────────────────────────────────────────────────────────────────────

func test_remove_item_decreases_quantity() -> void:
	_svc.on_item_add_confirmed(ITEM_A, 10, P1)
	var ok := _svc.remove_item(ITEM_A, P1, 4)
	assert_true(ok, "remove_item() muss true zurückgeben")
	assert_true(_svc.has_item(ITEM_A, P1, 6), "6 übrig nach remove 4 von 10")

func test_remove_all_clears_item() -> void:
	_svc.on_item_add_confirmed(ITEM_A, 5, P1)
	_svc.remove_item(ITEM_A, P1, 5)
	assert_false(_svc.has_item(ITEM_A, P1), "Item muss nach vollständigem Remove fehlen")

func test_remove_more_than_owned_returns_false() -> void:
	_svc.on_item_add_confirmed(ITEM_A, 2, P1)
	var ok := _svc.remove_item(ITEM_A, P1, 5)
	assert_false(ok, "remove_item() muss false zurückgeben wenn zu wenig")
	assert_true(_svc.has_item(ITEM_A, P1, 2), "State darf sich nicht geändert haben")

func test_remove_from_empty_returns_false() -> void:
	var ok := _svc.remove_item(ITEM_A, P1, 1)
	assert_false(ok, "remove_item() auf leerem Slot → false")

# ─────────────────────────────────────────────────────────────────────────────
# request_add_item — Slot-Limit, Gewichtslimit
# ─────────────────────────────────────────────────────────────────────────────

func test_request_add_known_item_succeeds() -> void:
	var ok := _svc.request_add_item(ITEM_A, P1, 1)
	assert_true(ok, "request_add_item() muss true für bekanntes Item zurückgeben")
	assert_true(_svc.has_item(ITEM_A, P1, 1), "Item muss danach vorhanden sein")

func test_request_add_unknown_item_returns_false() -> void:
	var ok := _svc.request_add_item("ghost_item", P1, 1)
	assert_false(ok, "Unbekanntes Item → false")

func test_weight_tracked_after_add() -> void:
	_svc.on_item_add_confirmed(ITEM_A, 5, P1)  # 5 × 2.0 kg = 10.0 kg
	var ws := _svc.get_weight_status(P1)
	assert_almost_eq(ws["current"], 10.0, 0.01, "Gewicht muss 10.0 kg sein")

func test_weight_tracked_after_remove() -> void:
	_svc.on_item_add_confirmed(ITEM_A, 5, P1)
	_svc.remove_item(ITEM_A, P1, 2)  # 3 × 2.0 = 6.0 kg
	var ws := _svc.get_weight_status(P1)
	assert_almost_eq(ws["current"], 6.0, 0.01, "Gewicht nach Remove: 6.0 kg")

func test_weight_limit_blocks_add() -> void:
	# Standardlimit: 50 kg. iron_ore = 2.0 kg. 25 Stück = 50.0 kg (Limit)
	_svc.on_item_add_confirmed(ITEM_A, 25, P1)  # 50 kg — exakt am Limit
	# log_oak = 3.0 kg — würde über Limit gehen
	var ok := _svc.request_add_item(ITEM_B, P1, 1)
	assert_false(ok, "Gewichtslimit muss weiteres Hinzufügen verhindern")

# ─────────────────────────────────────────────────────────────────────────────
# ADR-010 Round 55 — on_item_add_confirmed() Verteidigung in der Tiefe
# (Tier 3: "Server vertraut niemandem", nicht nur der request_add_item()-
# Konvention). Simuliert einen Aufrufer, der die Vorprüfung umgeht.
# ─────────────────────────────────────────────────────────────────────────────

func test_on_item_add_confirmed_rejects_over_weight_limit_directly() -> void:
	_svc.on_item_add_confirmed(ITEM_A, 25, P1)  # 50 kg — exakt am Limit
	_svc.on_item_add_confirmed(ITEM_B, 1, P1)   # Direktaufruf, umgeht request_add_item()
	assert_false(_svc.has_item(ITEM_B, P1, 1),
		"on_item_add_confirmed() muss das Gewichtslimit auch bei Direktaufruf durchsetzen.")

func test_on_item_add_confirmed_rejects_new_item_over_slot_limit_directly() -> void:
	for i in range(28):  # Default max_slots
		var id := "item_%d" % i
		_ds._items[id] = MockItemDef.new(id, 99, 0.1)
		_svc.on_item_add_confirmed(id, 1, P1)
	_ds._items["one_item_too_many"] = MockItemDef.new("one_item_too_many", 99, 0.1)
	var before := _svc.get_free_slots(P1)
	_svc.on_item_add_confirmed("one_item_too_many", 1, P1)
	assert_eq(_svc.get_free_slots(P1), before,
		"on_item_add_confirmed() darf bei vollen Slots keinen neuen Item-Typ akzeptieren, auch bei Direktaufruf.")

func test_on_item_add_confirmed_still_allows_stacking_existing_item_at_slot_limit() -> void:
	for i in range(28):
		var id := "item_%d" % i
		_ds._items[id] = MockItemDef.new(id, 99, 0.1)
		_svc.on_item_add_confirmed(id, 1, P1)
	_svc.on_item_add_confirmed("item_0", 3, P1)  # Stacking auf existierenden Slot, kein neuer Slot nötig
	assert_true(_svc.has_item("item_0", P1, 4),
		"Stacking auf einen bereits belegten Slot darf am Slotlimit nicht blockiert werden.")

# ─────────────────────────────────────────────────────────────────────────────
# get_free_slots
# ─────────────────────────────────────────────────────────────────────────────

func test_free_slots_decreases_on_new_item_type() -> void:
	var before := _svc.get_free_slots(P1)
	_svc.on_item_add_confirmed(ITEM_A, 1, P1)
	var after := _svc.get_free_slots(P1)
	assert_eq(after, before - 1, "Neues Item-Typ belegt einen Slot")

func test_free_slots_unchanged_on_stack_add() -> void:
	_svc.on_item_add_confirmed(ITEM_A, 1, P1)
	var before := _svc.get_free_slots(P1)
	_svc.on_item_add_confirmed(ITEM_A, 5, P1)  # Stacking, kein neuer Slot
	var after := _svc.get_free_slots(P1)
	assert_eq(after, before, "Stacking belegt keinen neuen Slot")

# ─────────────────────────────────────────────────────────────────────────────
# Multi-Tenanz (MIGRATION-010)
# ─────────────────────────────────────────────────────────────────────────────

func test_two_players_have_independent_state() -> void:
	_svc.on_item_add_confirmed(ITEM_A, 10, P1)
	_svc.on_item_add_confirmed(ITEM_A, 3,  P2)
	assert_true( _svc.has_item(ITEM_A, P1, 10), "Spieler 1: 10x iron_ore")
	assert_false(_svc.has_item(ITEM_A, P2, 10), "Spieler 2 hat keine 10x iron_ore")
	assert_true( _svc.has_item(ITEM_A, P2, 3),  "Spieler 2: 3x iron_ore")

func test_remove_from_player1_does_not_affect_player2() -> void:
	_svc.on_item_add_confirmed(ITEM_A, 5, P1)
	_svc.on_item_add_confirmed(ITEM_A, 5, P2)
	_svc.remove_item(ITEM_A, P1, 5)
	assert_false(_svc.has_item(ITEM_A, P1, 1), "Spieler 1 hat kein iron_ore mehr")
	assert_true( _svc.has_item(ITEM_A, P2, 5), "Spieler 2 unberührt")

# ─────────────────────────────────────────────────────────────────────────────
# Save-Interface
# ─────────────────────────────────────────────────────────────────────────────

func test_save_key_is_inventory() -> void:
	assert_eq(_svc.get_save_key(), "inventory", "SAVE_KEY muss 'inventory' sein")

func test_save_data_reflects_current_state() -> void:
	_svc.on_item_add_confirmed(ITEM_A, 7, P1)
	var sd := _svc.get_save_data()
	assert_true(sd.has(P1), "Save-Daten müssen den Player-1-Bucket (Key '%s') enthalten" % P1)
	var bucket := sd[P1] as Dictionary
	assert_true(bucket.has(ITEM_A), "iron_ore muss im Snapshot sein")
	# ADR-035 Phase 1: Wert ist jetzt ItemInstance.to_dict(), keine rohe int-Menge mehr.
	var entry := bucket[ITEM_A] as Dictionary
	assert_eq(int(entry["quantity"]), 7, "Menge muss 7 sein")
	assert_false(String(entry.get("uuid", "")).is_empty(), "Snapshot-Eintrag muss eine uuid tragen")

func test_save_data_empty_when_no_items() -> void:
	var sd := _svc.get_save_data()
	# Frische Instanz: kein einziger Player-Bucket existiert (kein _ensure_player()-
	# Aufruf ohne mindestens einen on_item_add_confirmed()) → leeres Dictionary.
	var has_items := false
	for pid_str in sd:
		var b := sd[pid_str] as Dictionary
		if not b.is_empty():
			has_items = true
	assert_false(has_items, "Leeres Inventar → keine Items im Snapshot")

# ─────────────────────────────────────────────────────────────────────────────
# Save-Round-Trip (A-04 / E-02)
# ─────────────────────────────────────────────────────────────────────────────

func test_round_trip_restores_items() -> void:
	# Phase 1: State aufbauen
	_svc.on_item_add_confirmed(ITEM_A, 12, P1)
	_svc.on_item_add_confirmed(ITEM_B, 3, P1)
	var snapshot := _svc.get_save_data()

	# Phase 2: neue Instanz + Restore
	var svc2 := InventorySystem.new()
	svc2.configure(ServiceDeps.from_dict({ServiceKeys.DATA: _ds, ServiceKeys.EVENT_BUS: _bus}))
	svc2._restore_from_save(snapshot)

	assert_true(svc2.has_item(ITEM_A, P1, 12), "Round-Trip: 12x iron_ore muss wiederhergestellt sein")
	assert_true(svc2.has_item(ITEM_B, P1, 3),  "Round-Trip: 3x log_oak muss wiederhergestellt sein")

	svc2.on_cleanup()

func test_round_trip_empty_save_produces_empty_inventory() -> void:
	var svc2 := InventorySystem.new()
	svc2.configure(ServiceDeps.from_dict({ServiceKeys.DATA: _ds, ServiceKeys.EVENT_BUS: _bus}))
	svc2._restore_from_save({})

	assert_false(svc2.has_item(ITEM_A, P1), "Nach leerem Restore: kein iron_ore")
	svc2.on_cleanup()

# ─────────────────────────────────────────────────────────────────────────────
# ADR-035 Phase 1 — ItemInstance-uuid (Round 88)
# ─────────────────────────────────────────────────────────────────────────────

func test_get_all_items_exposes_uuid() -> void:
	_svc.on_item_add_confirmed(ITEM_A, 1, P1)
	var all := _svc.get_all_items(P1)
	assert_eq(all.size(), 1)
	assert_false(String(all[0].get("uuid", "")).is_empty(), "get_all_items()-Eintrag muss eine uuid tragen")

func test_uuid_stable_across_stacking() -> void:
	_svc.on_item_add_confirmed(ITEM_A, 3, P1)
	var uuid_before: String = _svc.get_item_instance(P1, ITEM_A).uuid
	_svc.on_item_add_confirmed(ITEM_A, 4, P1)  # Stapelt auf denselben Slot
	var uuid_after: String = _svc.get_item_instance(P1, ITEM_A).uuid
	assert_eq(uuid_after, uuid_before, "Stacking auf denselben Slot darf die uuid nicht ändern")

func test_uuid_differs_between_players() -> void:
	_svc.on_item_add_confirmed(ITEM_A, 1, P1)
	_svc.on_item_add_confirmed(ITEM_A, 1, P2)
	var uuid_p1: String = _svc.get_item_instance(P1, ITEM_A).uuid
	var uuid_p2: String = _svc.get_item_instance(P2, ITEM_A).uuid
	assert_ne(uuid_p1, uuid_p2, "Zwei unabhängige Spieler-Instanzen dürfen nicht dieselbe uuid teilen")

func test_get_item_instance_returns_null_when_absent() -> void:
	assert_null(_svc.get_item_instance(P1, ITEM_A), "Kein Bestand → get_item_instance() muss null zurückgeben")

func test_round_trip_preserves_uuid() -> void:
	_svc.on_item_add_confirmed(ITEM_A, 5, P1)
	var uuid_before: String = _svc.get_item_instance(P1, ITEM_A).uuid
	var snapshot := _svc.get_save_data()

	var svc2 := InventorySystem.new()
	svc2.configure(ServiceDeps.from_dict({ServiceKeys.DATA: _ds, ServiceKeys.EVENT_BUS: _bus}))
	svc2._restore_from_save(snapshot)

	var uuid_after: String = svc2.get_item_instance(P1, ITEM_A).uuid
	assert_eq(uuid_after, uuid_before, "Round-Trip muss die uuid erhalten, nicht neu vergeben")
	svc2.on_cleanup()

func test_round_trip_multi_tenant() -> void:
	_svc.on_item_add_confirmed(ITEM_A, 5, P1)
	_svc.on_item_add_confirmed(ITEM_A, 9, P2)
	var snapshot := _svc.get_save_data()

	var svc2 := InventorySystem.new()
	svc2.configure(ServiceDeps.from_dict({ServiceKeys.DATA: _ds, ServiceKeys.EVENT_BUS: _bus}))
	svc2._restore_from_save(snapshot)

	assert_true(svc2.has_item(ITEM_A, P1, 5), "Spieler 1: 5x nach Round-Trip")
	assert_true(svc2.has_item(ITEM_A, P2, 9), "Spieler 2: 9x nach Round-Trip")
	svc2.on_cleanup()

# ─────────────────────────────────────────────────────────────────────────────
# ADR-038 — Schutz-Flags werden mit-serialisiert (kein eigener Save-Bucket)
# ─────────────────────────────────────────────────────────────────────────────

func test_round_trip_preserves_protection_flags() -> void:
	_svc.on_item_add_confirmed(ITEM_A, 1, P1)
	var inst := _svc.get_item_instance(P1, ITEM_A)
	inst.is_pve_death_protected = true
	inst.is_pvp_protected       = true
	# is_theft_protected bewusst false gelassen — Round-Trip muss auch den
	# "nicht gesetzt"-Fall korrekt erhalten, nicht nur "auf true umkippen".
	var snapshot := _svc.get_save_data()

	var svc2 := InventorySystem.new()
	svc2.configure(ServiceDeps.from_dict({ServiceKeys.DATA: _ds, ServiceKeys.EVENT_BUS: _bus}))
	svc2._restore_from_save(snapshot)

	var restored := svc2.get_item_instance(P1, ITEM_A)
	assert_true(restored.is_pve_death_protected, "PvE-Schutz muss Round-Trip überleben")
	assert_true(restored.is_pvp_protected, "PvP-Schutz muss Round-Trip überleben")
	assert_false(restored.is_theft_protected, "Nicht gesetzter Diebstahlschutz muss false bleiben")
	svc2.on_cleanup()

func test_pre_adr038_save_without_protection_fields_defaults_to_unprotected() -> void:
	# Alte Saves kennen die drei is_*_protected-Keys nicht — from_dict() muss
	# das über dict.get()-Defaults abfangen statt zu crashen.
	var legacy_snapshot := {
		P1: {
			ITEM_A: {"item_id": ITEM_A, "quantity": 1, "durability": 100.0, "uuid": "legacy-uuid"}
		}
	}
	var svc2 := InventorySystem.new()
	svc2.configure(ServiceDeps.from_dict({ServiceKeys.DATA: _ds, ServiceKeys.EVENT_BUS: _bus}))
	svc2._restore_from_save(legacy_snapshot)

	var restored := svc2.get_item_instance(P1, ITEM_A)
	assert_not_null(restored, "Legacy-Save ohne Schutz-Felder muss trotzdem laden")
	assert_false(restored.is_pve_death_protected)
	assert_false(restored.is_theft_protected)
	assert_false(restored.is_pvp_protected)
	svc2.on_cleanup()

# ─────────────────────────────────────────────────────────────────────────────
# inject_network_bridge() — Round 113 Nachtrag, siehe
# method_reference_coverage.py-Fund (Phase-C8-Late-Inject, ADR-022)
# ─────────────────────────────────────────────────────────────────────────────

func test_inject_network_bridge_sets_the_reference() -> void:
	var bridge: NetworkBridge = add_child_autofree(NetworkBridge.new())
	_svc.inject_network_bridge(bridge)
	assert_same(_svc._network, bridge)

func test_inject_network_bridge_connects_economy_state_received() -> void:
	var bridge: NetworkBridge = add_child_autofree(NetworkBridge.new())
	assert_eq(bridge.economy_state_received.get_connections().size(), 0)
	_svc.inject_network_bridge(bridge)
	assert_eq(bridge.economy_state_received.get_connections().size(), 1,
		"inject_network_bridge() muss _connect_economy_sync() erneut anstoßen (Late-Inject-Fall, siehe ADR-022)")

func test_inject_network_bridge_does_not_double_connect_when_called_twice() -> void:
	var bridge: NetworkBridge = add_child_autofree(NetworkBridge.new())
	_svc.inject_network_bridge(bridge)
	_svc.inject_network_bridge(bridge)
	assert_eq(bridge.economy_state_received.get_connections().size(), 1,
		"_connect_economy_sync() prüft is_connected() — zweimaliges Inject darf nicht doppelt verbinden")
