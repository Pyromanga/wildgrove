# res://tests/unit/test_wearable_catalog.gd
extends GutTest

## Tests für WearableCatalog / WearableDefinition: Kleidung als echte Items, erzeugt aus dem
## Look-Katalog. Wichtigste Garantie: Item und Optik können nie auseinanderlaufen.

func test_every_slot_has_items() -> void:
	for slot in WearableCatalog.SLOT_ORDER:
		var found := false
		for item in WearableCatalog.all_items().values():
			if (item as WearableDefinition).wear_slot == slot:
				found = true
				break
		assert_true(found, "Slot '%s' hat kein einziges Item." % slot)

func test_item_ids_are_prefixed_unique_and_names_set() -> void:
	var names: Dictionary = {}
	for id in WearableCatalog.all_items().keys():
		var item := WearableCatalog.all_items()[id] as WearableDefinition
		assert_true(String(id).begins_with(WearableCatalog.ITEM_PREFIX), "ID '%s' ohne Präfix." % id)
		assert_eq(item.id, String(id))
		assert_false(item.display_name.is_empty(), "Item '%s' ohne Namen." % id)
		assert_false(names.has(item.display_name), "Doppelter Anzeigename '%s'." % item.display_name)
		names[item.display_name] = true

func test_look_values_are_valid_catalog_ids() -> void:
	for item in WearableCatalog.all_items().values():
		var def := item as WearableDefinition
		assert_false(def.look_values.is_empty(), "Item '%s' setzt nichts im Look." % def.id)
		for key in def.look_values.keys():
			assert_true(CharacterLook.option_ids(String(key)).has(def.look_values[key]),
				"Item '%s': %s=%s ist keine gültige Look-Option." % [def.id, key, def.look_values[key]])
			assert_true(CharacterLook.is_worn_key(String(key)), "'%s' müsste ein worn-Feld sein." % key)

func test_wearing_every_item_roundtrips_through_the_look() -> void:
	for id in WearableCatalog.all_items().keys():
		var item := WearableCatalog.all_items()[id] as WearableDefinition
		var look := WearableCatalog.wear_in_look(CharacterLook.default_look(), String(id))
		assert_eq(WearableCatalog.item_id_for_slot(item.wear_slot, look), String(id), "Roundtrip schlägt fehl für '%s'." % id)

func test_default_look_wears_shirt_pants_and_shoes() -> void:
	var outfit := WearableCatalog.worn_outfit(CharacterLook.default_look())
	assert_true(outfit.has("shirt"))
	assert_true(outfit.has("pants"))
	assert_true(outfit.has("shoes"))
	assert_false(outfit.has("hat"), "Default trägt keinen Hut.")

func test_take_off_empties_the_slot() -> void:
	var naked := WearableCatalog.take_off_in_look(CharacterLook.default_look(), "shirt")
	assert_eq(naked["shirt"], "none")
	assert_eq(WearableCatalog.item_id_for_slot("shirt", naked), "")
	assert_false(WearableCatalog.worn_outfit(naked).has("shirt"))
	assert_true(WearableCatalog.worn_outfit(naked).has("pants"), "Andere Slots bleiben unberührt.")

func test_look_patch_rejects_wrong_slot_and_unknown_ids() -> void:
	assert_true(WearableCatalog.look_patch("shirt", "cl_pants_navy_long").is_empty(), "Hose passt nicht in den Oberteil-Slot.")
	assert_true(WearableCatalog.look_patch("shirt", "does_not_exist").is_empty())
	assert_true(WearableCatalog.look_patch("not_a_slot", "cl_shirt_wald_tshirt").is_empty())
	assert_eq(WearableCatalog.look_patch("shirt", ""), {"shirt": "none"}, "Leere ID = ausziehen.")
	assert_eq(WearableCatalog.look_patch("shirt", "cl_shirt_wald_tshirt"), {"shirt": "wald", "shirt_style": "tshirt"})

func test_fixed_color_hats_ignore_hat_color() -> void:
	var look := CharacterLook.sanitize({"hat": "tophat", "hat_color": "brown"})
	assert_eq(WearableCatalog.item_id_for_slot("hat", look), "cl_hat_tophat_black")
	var hard := CharacterLook.sanitize({"hat": "hardhat", "hat_color": "red"})
	assert_eq(WearableCatalog.item_id_for_slot("hat", hard), "cl_hat_hardhat_yellow")

func test_every_armor_item_is_known_to_the_look_catalog() -> void:
	# Jede Rüstungs-.tres muss im Look-Katalog (armor_*) stehen, sonst bliebe sie unsichtbar.
	var checked := 0
	for path in DataManifest.ITEMS:
		if not String(path).contains("/armor/"):
			continue
		var armor := load(String(path)) as ArmorDefinition
		assert_not_null(armor, "'%s' ist keine ArmorDefinition." % path)
		if armor == null:
			continue
		assert_eq(WearableCatalog.armor_slot_of_id(armor.id), armor.get_slot_id(), "Rüstung '%s' fehlt im Look-Katalog." % armor.id)
		checked += 1
	assert_gt(checked, 0, "Keine Rüstungs-Items im DataManifest gefunden.")

func test_slot_of_item() -> void:
	var shirt := WearableCatalog.get_item("cl_shirt_wald_tshirt")
	assert_eq(WearableCatalog.slot_of_item(shirt), "shirt")
	var armor := ArmorDefinition.new()
	armor.armor_slot = ArmorDefinition.ArmorSlot.BOOTS
	assert_eq(WearableCatalog.slot_of_item(armor), "boots")
	assert_eq(WearableCatalog.slot_of_item(WeaponDefinition.new()), "")

func test_wear_slots_do_not_collide_with_other_equipment_slots() -> void:
	for slot in WearableCatalog.SLOT_ORDER:
		assert_false(ArmorDefinition.is_armor_slot(String(slot)), "Slot '%s' kollidiert mit Rüstung." % slot)
		assert_false(String(slot) in ["weapon", "tool", "offhand"], "Slot '%s' kollidiert mit Waffe/Werkzeug." % slot)

func test_register_into_does_not_overwrite_existing_entries() -> void:
	var existing := ItemDefinition.new()
	existing.id = "cl_shirt_wald_tshirt"
	var target: Dictionary = {existing.id: existing}
	WearableCatalog.register_into(target)
	assert_eq(target[existing.id], existing, "Eine vorhandene (z. B. .tres-)Definition hat Vorrang.")
	assert_gt(target.size(), 50)
