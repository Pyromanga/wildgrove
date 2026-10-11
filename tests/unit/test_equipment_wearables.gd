# res://tests/unit/test_equipment_wearables.gd
extends GutTest

## Tests für anziehbare Kleidung im EquipmentService: Inventar ↔ Look-Umbuchung, Slot-/Besitz-
## Prüfung, Rüstungs-Spiegel, Schutz vor Look-Updates und Persistenz. Aufbau wie
## test_equipment_service_r4.gd (Tier 1/Solo: Aufrufe laufen direkt auf der Autorität).

class MockDataService extends DataService:
	pass

class MockSaveSystem extends SaveSystem:
	var _preset: Dictionary = {}
	func register_save_provider(_p: Object) -> void:
		pass
	func get_state_for(key: String) -> Dictionary:
		return _preset.get(key, {})

const P1 := "p1"
const DEFAULT_SHIRT := "cl_shirt_unbestimmt_tshirt"
const WALD_SHIRT := "cl_shirt_wald_tshirt"

var _equipment: EquipmentService
var _inventory: InventorySystem
var _creation: CharacterCreationService
var _data: MockDataService
var _save: MockSaveSystem
var _mods: StatModifierService
var _bus: MockEventBus

func before_each() -> void:
	_mods = StatModifierService.new()
	_save = MockSaveSystem.new()
	_data = MockDataService.new()
	_bus = MockEventBus.new()
	WearableCatalog.register_into(_data._items)
	_inventory = InventorySystem.new()
	_inventory.configure(ServiceDeps.from_dict({
		ServiceKeys.DATA: _data,
		ServiceKeys.SAVE_SYSTEM: _save,
		ServiceKeys.EVENT_BUS: _bus,
	}))
	_equipment = EquipmentService.new()
	_equipment.configure(ServiceDeps.from_dict({
		"stat_modifiers": _mods,
		"savesystem": _save,
		"data": _data,
		"inventory": _inventory,
	}))
	_creation = CharacterCreationService.new()
	_creation.configure(ServiceDeps.from_dict({ServiceKeys.SAVE_SYSTEM: _save}))
	_equipment.inject_wearables(_creation)

func after_each() -> void:
	_equipment.on_cleanup()
	_inventory.on_cleanup()
	_mods.on_cleanup()

func _give(item_id: String) -> void:
	_inventory.on_item_add_confirmed(item_id, 1, P1)

func _armor(id: String, slot: ArmorDefinition.ArmorSlot) -> ArmorDefinition:
	var a := ArmorDefinition.new()
	a.id = id
	a.display_name = id
	a.armor_slot = slot
	return a

# ── Anziehen ────────────────────────────────────────────────────────────────

func test_new_player_starts_dressed_from_the_look() -> void:
	assert_eq(_creation.get_worn_item_id(P1, "shirt"), DEFAULT_SHIRT)
	assert_true(_equipment.is_equipped("shirt", P1))
	assert_eq(_equipment.get_equipped("shirt", P1).id, DEFAULT_SHIRT)
	assert_false(_equipment.is_equipped("hat", P1))

func test_wearing_moves_item_from_inventory_to_body() -> void:
	_give(WALD_SHIRT)
	_equipment.on_equip_confirmed("shirt", WALD_SHIRT, P1)
	assert_eq(_creation.get_worn_item_id(P1, "shirt"), WALD_SHIRT)
	assert_eq(_creation.get_look(P1)["shirt"], "wald", "Der Look (= was alle sehen) zeigt das neue Hemd.")
	assert_false(_inventory.has_item(WALD_SHIRT, P1), "Angezogenes Teil verlässt das Inventar.")

func test_swapping_returns_the_previous_piece_to_the_inventory() -> void:
	_give(WALD_SHIRT)
	_equipment.on_equip_confirmed("shirt", WALD_SHIRT, P1)
	assert_true(_inventory.has_item(DEFAULT_SHIRT, P1), "Das bisherige Hemd landet im Inventar.")

func test_take_off_returns_item_and_leaves_slot_empty() -> void:
	_equipment.on_unequip_confirmed("shirt", P1)
	assert_eq(_creation.get_worn_item_id(P1, "shirt"), "")
	assert_eq(_creation.get_look(P1)["shirt"], "none")
	assert_false(_equipment.is_equipped("shirt", P1))
	assert_true(_inventory.has_item(DEFAULT_SHIRT, P1))

func test_dress_again_after_take_off_is_a_full_cycle() -> void:
	_equipment.on_unequip_confirmed("pants", P1)
	var pants_id := "cl_pants_navy_long"
	assert_true(_inventory.has_item(pants_id, P1))
	_equipment.on_equip_confirmed("pants", pants_id, P1)
	assert_eq(_creation.get_worn_item_id(P1, "pants"), pants_id)
	assert_false(_inventory.has_item(pants_id, P1))

func test_taking_off_an_empty_slot_changes_nothing() -> void:
	_equipment.on_unequip_confirmed("hat", P1)
	assert_eq(_creation.get_look(P1)["hat"], "none")

# ── Verweigerungen ──────────────────────────────────────────────────────────

func test_wearing_without_owning_is_refused() -> void:
	_equipment.on_equip_confirmed("shirt", WALD_SHIRT, P1)
	assert_eq(_creation.get_worn_item_id(P1, "shirt"), DEFAULT_SHIRT)

func test_wrong_slot_is_refused_and_item_stays_in_inventory() -> void:
	_give("cl_pants_navy_long")
	_equipment.on_equip_confirmed("shirt", "cl_pants_navy_long", P1)
	assert_eq(_creation.get_worn_item_id(P1, "shirt"), DEFAULT_SHIRT)
	assert_true(_inventory.has_item("cl_pants_navy_long", P1))

func test_non_clothing_cannot_enter_a_clothing_slot() -> void:
	var sword := WeaponDefinition.new()
	sword.id = "test_sword"
	sword.display_name = "Schwert"
	_data._items[sword.id] = sword
	_give(sword.id)
	_equipment.on_equip_confirmed("shirt", sword.id, P1)
	assert_eq(_creation.get_worn_item_id(P1, "shirt"), DEFAULT_SHIRT)
	assert_true(_inventory.has_item(sword.id, P1))

func test_clothing_cannot_enter_weapon_or_armor_slots() -> void:
	_give(WALD_SHIRT)
	_equipment.on_equip_confirmed("weapon", WALD_SHIRT, P1)
	_equipment.on_equip_confirmed("chest", WALD_SHIRT, P1)
	assert_false(_equipment.is_equipped("weapon", P1))
	assert_false(_equipment.is_equipped("chest", P1))
	assert_true(_inventory.has_item(WALD_SHIRT, P1))

# ── Look-Updates dürfen keine Kleidung setzen ───────────────────────────────

func test_look_update_cannot_change_worn_state_but_body_still_works() -> void:
	_creation.on_set_look_confirmed(P1, {"skin": "dark", "shirt": "red", "hat": "wizard", "armor_chest": "iron_chestplate"})
	var look := _creation.get_look(P1)
	assert_eq(look["skin"], "dark")
	assert_eq(look["shirt"], "unbestimmt")
	assert_eq(look["hat"], "none")
	assert_eq(look["armor_chest"], "none")

func test_sex_can_be_changed_through_the_look_update() -> void:
	_creation.on_set_look_confirmed(P1, {"sex": "female"})
	assert_eq(_creation.get_look(P1)["sex"], "female")
	assert_eq(_creation.get_worn_item_id(P1, "shirt"), DEFAULT_SHIRT, "Kleidung bleibt beim Wechsel erhalten.")

# ── Rüstung ─────────────────────────────────────────────────────────────────

func test_armor_is_mirrored_into_the_look_and_removed_again() -> void:
	_equipment.equip("helmet", _armor("iron_helmet", ArmorDefinition.ArmorSlot.HELMET), P1)
	assert_eq(_creation.get_look(P1)["armor_helmet"], "iron_helmet")
	_equipment.unequip("helmet", P1)
	assert_eq(_creation.get_look(P1)["armor_helmet"], "none")

func test_armor_unknown_to_the_look_catalog_does_not_crash() -> void:
	_equipment.equip("boots", _armor("mythril_boots", ArmorDefinition.ArmorSlot.BOOTS), P1)
	assert_eq(_creation.get_look(P1)["armor_boots"], "none", "Unbekannte Rüstung bleibt unsichtbar, wirkt aber weiter.")
	assert_true(_equipment.is_equipped("boots", P1))

func test_inject_wearables_mirrors_armor_loaded_from_save() -> void:
	var helmet := _armor("steel_helmet", ArmorDefinition.ArmorSlot.HELMET)
	_data._items[helmet.id] = helmet
	var save := MockSaveSystem.new()
	save._preset["equipment"] = {P1: {"helmet": helmet.id}}
	var eq := EquipmentService.new()
	eq.configure(ServiceDeps.from_dict({"stat_modifiers": _mods, "savesystem": save, "data": _data}))
	eq.inject_wearables(_creation)
	assert_eq(_creation.get_look(P1)["armor_helmet"], "steel_helmet", "Geladene Rüstung muss wieder am Körper erscheinen.")
	eq.on_cleanup()

# ── Signale + Persistenz ────────────────────────────────────────────────────

func test_wearing_emits_equipment_changed_for_the_ui() -> void:
	watch_signals(_equipment)
	_give(WALD_SHIRT)
	_equipment.on_equip_confirmed("shirt", WALD_SHIRT, P1)
	assert_signal_emitted(_equipment, "equipment_changed")

func test_worn_clothing_survives_save_and_load() -> void:
	_give(WALD_SHIRT)
	_equipment.on_equip_confirmed("shirt", WALD_SHIRT, P1)
	_equipment.on_unequip_confirmed("pants", P1)
	var save2 := MockSaveSystem.new()
	save2._preset[_creation.get_save_key()] = _creation.get_save_data()
	var creation2 := CharacterCreationService.new()
	creation2.configure(ServiceDeps.from_dict({ServiceKeys.SAVE_SYSTEM: save2}))
	assert_eq(creation2.get_worn_item_id(P1, "shirt"), WALD_SHIRT)
	assert_eq(creation2.get_worn_item_id(P1, "pants"), "", "Auch 'nackt' wird gespeichert.")

func test_old_save_with_clothing_fields_loads_as_worn_outfit() -> void:
	# Alt-Spielstand: Look ohne worn-Zusatzfelder (scarf/back/armor_*), aber mit Hemd/Hose.
	var old_look := {"skin": "dark", "shirt": "wald", "shirt_style": "longsleeve", "pants": "olive", "shoes": "tan"}
	var save2 := MockSaveSystem.new()
	save2._preset[_creation.get_save_key()] = {"look": {P1: old_look}}
	var creation2 := CharacterCreationService.new()
	creation2.configure(ServiceDeps.from_dict({ServiceKeys.SAVE_SYSTEM: save2}))
	assert_eq(creation2.get_worn_item_id(P1, "shirt"), "cl_shirt_wald_longsleeve")
	assert_eq(creation2.get_worn_item_id(P1, "pants"), "cl_pants_olive_long")
	assert_eq(creation2.get_look(P1)["armor_chest"], "none")
	assert_eq(creation2.get_look(P1)["sex"], "male")
