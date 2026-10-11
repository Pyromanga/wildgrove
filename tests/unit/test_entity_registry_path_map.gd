# res://tests/unit/test_entity_registry_path_map.gd
extends GutTest

## Tests für EntityRegistry.get_path_to_type_map() (F-1).
##
## Strategie: EntityRegistry ist ein RefCounted — kein add_child nötig.
## Direkt instanziieren, register() aufrufen, Invarianten prüfen.
##
## Abgedeckt:
##   - Leere Registry → leere Map
##   - Registrierter Typ → Pfad erscheint als Key
##   - Registrierter Typ → type_id erscheint als Value
##   - Zwei Typen → beide in Map
##   - Bijektivität: jeder Pfad zeigt auf genau einen type_id

var _registry: EntityRegistry

func before_each() -> void:
	_registry = EntityRegistry.new()

func after_each() -> void:
	_registry = null

# ─────────────────────────────────────────────────────────────────────────────
# get_path_to_type_map — Grundverhalten
# ─────────────────────────────────────────────────────────────────────────────

func test_empty_registry_returns_empty_map() -> void:
	var map := _registry.get_path_to_type_map()
	assert_eq(map.size(), 0, "Leere Registry → leere Map")

func test_registered_type_path_appears_as_key() -> void:
	# ResourceLoader.exists() schlägt fehl wenn Pfad nicht existiert —
	# wir mocken das indem wir register() direkt auf _definitions schreiben.
	_registry._definitions["oak_tree"] = {"path": "res://scripts/world/objects/OakTree.gd", "group": "trees"}
	var map := _registry.get_path_to_type_map()
	assert_true(map.has("res://scripts/world/objects/OakTree.gd"),
		"Registrierter Pfad muss als Key in der Map erscheinen.")

func test_registered_type_id_appears_as_value() -> void:
	_registry._definitions["oak_tree"] = {"path": "res://scripts/world/objects/OakTree.gd", "group": "trees"}
	var map := _registry.get_path_to_type_map()
	assert_eq(map.get("res://scripts/world/objects/OakTree.gd", ""), "oak_tree",
		"Der type_id muss als Value für den Pfad-Key stehen.")

func test_two_types_both_in_map() -> void:
	_registry._definitions["oak_tree"] = {"path": "res://scripts/world/objects/OakTree.gd", "group": "trees"}
	_registry._definitions["player"]   = {"path": "res://scripts/entities/player/Player.gd", "group": "player"}
	var map := _registry.get_path_to_type_map()
	assert_eq(map.size(), 2, "Zwei registrierte Typen → zwei Einträge in der Map.")

func test_entry_with_empty_path_is_excluded() -> void:
	# Direkt in _definitions schreiben um register()-Validierung zu umgehen
	_registry._definitions["broken_type"] = {"path": "", "group": ""}
	var map := _registry.get_path_to_type_map()
	assert_false(map.has(""),
		"Leere Pfade dürfen nicht als Key in der Map erscheinen.")

func test_map_is_bijective_for_distinct_paths() -> void:
	_registry._definitions["oak_tree"] = {"path": "res://scripts/world/objects/OakTree.gd", "group": "trees"}
	_registry._definitions["iron_ore"] = {"path": "res://scripts/world/objects/IronOre.gd", "group": "ores"}
	var map := _registry.get_path_to_type_map()
	# Alle Values sind eindeutig (kein type_id erscheint zweimal)
	var values := map.values()
	var unique := {}
	for v in values:
		unique[v] = true
	assert_eq(unique.size(), values.size(),
		"Jeder type_id darf nur einmal als Value vorkommen (Bijektivität).")

func test_map_does_not_share_reference_with_definitions() -> void:
	_registry._definitions["oak_tree"] = {"path": "res://scripts/world/objects/OakTree.gd", "group": "trees"}
	var map := _registry.get_path_to_type_map()
	# Nachträgliche Änderung an _definitions ändert nicht die bereits zurückgegebene Map
	_registry._definitions["new_type"] = {"path": "res://scripts/new.gd", "group": ""}
	assert_eq(map.size(), 1,
		"Die zurückgegebene Map ist eine Kopie — nachträgliche Registry-Änderungen berühren sie nicht.")

# ─────────────────────────────────────────────────────────────────────────────
# Alle fünf HarvestableEntity-Typen in der Map (P1-Fix)
# ─────────────────────────────────────────────────────────────────────────────

func test_all_five_harvestable_types_in_registry() -> void:
	## Stellt sicher dass alle 5 Typen registriert sind — nicht nur oak_tree + iron_ore.
	for type_id in ["oak_tree", "willow_tree", "maple_tree", "iron_ore", "copper_ore"]:
		_registry._definitions[type_id] = {
			"path": "res://scripts/world/objects/%s.gd" % type_id.capitalize(),
			"group": "trees" if "tree" in type_id else "ores"
		}
	var map := _registry.get_path_to_type_map()
	assert_true(map.values().has("willow_tree"), "willow_tree muss in der Path-Map sein")
	assert_true(map.values().has("maple_tree"),  "maple_tree muss in der Path-Map sein")
	assert_true(map.values().has("copper_ore"),  "copper_ore muss in der Path-Map sein")
	assert_eq(map.size(), 5, "Alle 5 Typen müssen in der Map erscheinen")

func test_willow_tree_path_resolves_to_correct_type_id() -> void:
	_registry._definitions["willow_tree"] = {
		"path": "res://scripts/world/objects/WillowTree.gd", "group": "trees"
	}
	var map := _registry.get_path_to_type_map()
	assert_eq(
		map.get("res://scripts/world/objects/WillowTree.gd", ""),
		"willow_tree",
		"WillowTree.gd muss auf type_id 'willow_tree' auflösen"
	)

func test_copper_ore_path_resolves_to_correct_type_id() -> void:
	_registry._definitions["copper_ore"] = {
		"path": "res://scripts/world/objects/CopperOre.gd", "group": "ores"
	}
	var map := _registry.get_path_to_type_map()
	assert_eq(
		map.get("res://scripts/world/objects/CopperOre.gd", ""),
		"copper_ore",
		"CopperOre.gd muss auf type_id 'copper_ore' auflösen"
	)
