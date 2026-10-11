# res://tests/unit/test_plants_content.gd
extends GutTest

## Konsistenz der Kräuter-/Blumen-Inhalte (Kräuterkunde "herbalism", Gartenkunde "gardening").
## Wie beim Hain-Skill-Test hängen die Teile nur über Strings zusammen: PlantCatalog <-> Items <->
## LootTables <-> Crops <-> Manifest <-> Registry <-> Biome <-> Respawn <-> Shop <-> Dorf-Felder.
## Fehlt ein Glied, passiert nichts Lautes — dieser Test macht es laut.
## Hinweis: ohne Godot-Binary geschrieben, beim ersten `make test-gd` beobachten.

const SKILL_IDS: Array[String] = ["herbalism", "gardening"]

func _manifest_has(list: Array[String], path_part: String) -> bool:
	for p: String in list:
		if p.contains(path_part):
			return true
	return false

func _item(id: String) -> ItemDefinition:
	for path: String in DataManifest.ITEMS:
		var it := load(path) as ItemDefinition
		if it != null and it.id == id:
			return it
	return null

# ── Katalog ─────────────────────────────────────────────

func test_catalog_has_twelve_plants_in_both_skills() -> void:
	assert_eq(PlantCatalog.ids().size(), 12)
	var skills := {}
	for id in PlantCatalog.ids():
		skills[PlantCatalog.get_plant(id)["skill"]] = true
	assert_true(skills.has("herbalism") and skills.has("gardening"))

func test_every_plant_has_all_fields_and_a_real_fact() -> void:
	for id in PlantCatalog.ids():
		var p := PlantCatalog.get_plant(id)
		for key in ["name", "latin", "skill", "wild", "harvest_item", "seed_item", "xp", "field_xp", "growth", "shop_price", "fact", "look"]:
			assert_true(p.has(key), "%s: Feld '%s' fehlt" % [id, key])
		assert_true(p["skill"] in SKILL_IDS, "%s: unbekannter Skill" % id)
		assert_gt(String(p["fact"]).length(), 30, "%s: Fakt fehlt" % id)
		assert_lte(String(p["fact"]).length(), 200, "%s: Fakt zu lang (Guide: ein Satz)" % id)
		assert_true(PlantCatalog.inspect_text(id).contains("Wusstest du?"), "%s: Zwei-Ebenen-Regel" % id)

func test_look_styles_are_known_to_visual_builder() -> void:
	var styles := ["daisy", "umbel", "rosette", "nettle", "cushion", "cup", "spike"]
	for id in PlantCatalog.ids():
		assert_true(String(PlantCatalog.get_plant(id)["look"]["style"]) in styles, "%s: Stil unbekannt" % id)

func test_visual_builder_builds_meshes_for_every_style() -> void:
	for id in PlantCatalog.ids():
		var root := Node3D.new()
		autofree(root)
		PlantVisualBuilder.build(root, PlantCatalog.get_plant(id)["look"])
		assert_gt(root.get_child_count(), 0, "%s: keine Meshes" % id)

# ── Daten ───────────────────────────────────────────────

func test_items_loot_and_crops_exist_and_link_up() -> void:
	for id in PlantCatalog.ids():
		var p := PlantCatalog.get_plant(id)
		var seed_def := _item(p["seed_item"])
		assert_not_null(_item(p["harvest_item"]), "%s: Ernte-Item nicht im Manifest" % id)
		assert_not_null(seed_def, "%s: Samen-Item nicht im Manifest" % id)
		assert_eq(seed_def.plants_crop_id, id, "%s: plants_crop_id des Samens" % id)
		var crop := load("res://data/crops/%s.tres" % id) as FarmCropDefinition
		assert_not_null(crop, "%s: Crop fehlt" % id)
		assert_eq(crop.id, id)
		assert_eq(crop.seed_item_id, p["seed_item"])
		assert_eq(crop.skill_id, p["skill"], "%s: XP-Skill des Feldes" % id)
		assert_eq(crop.harvest_loot_table_id, PlantCatalog.field_loot_id(id))
		assert_true(_manifest_has(DataManifest.CROPS, "/%s.tres" % id), "%s: Crop nicht im Manifest" % id)
		var field_loot := load("res://data/loot_tables/%s.tres" % crop.harvest_loot_table_id) as LootTable
		assert_not_null(field_loot, "%s: Feld-LootTable fehlt" % id)
		assert_true(_manifest_has(DataManifest.LOOT_TABLES, crop.harvest_loot_table_id), "%s: Feld-LootTable muss im Manifest stehen (DataService lädt per id)" % id)

func test_wild_loot_tables_exist_but_are_not_in_manifest() -> void:
	# Skill-Guide 5.2: Ernte-Tabellen per load() am Objekt, NICHT im Manifest (sonst Wiki-Kategorie "drops").
	for id in PlantCatalog.wild_ids():
		var loot := load(PlantCatalog.wild_loot_path(id)) as LootTable
		assert_not_null(loot, "%s: wilde LootTable fehlt" % id)
		assert_false(_manifest_has(DataManifest.LOOT_TABLES, "loot_plant_%s" % id), "%s: gehört nicht ins Manifest" % id)
		var items: Array[String] = []
		for e in loot.entries:
			items.append(e.item_id)
		assert_true(PlantCatalog.get_plant(id)["harvest_item"] in items, "%s: Tabelle gibt das Ernte-Item" % id)

func test_skills_registered_and_follow_two_layer_rule() -> void:
	for sid in SKILL_IDS:
		var found: SkillDefinition = null
		for path: String in DataManifest.SKILLS:
			var def := load(path) as SkillDefinition
			if def != null and def.id == sid:
				found = def
		assert_not_null(found, "%s nicht im Manifest" % sid)
		assert_true(found.description.contains("Wusstest du?"))
		assert_lte(found.description.length(), 260)

# ── Welt ────────────────────────────────────────────────

func test_wild_plants_are_registered_known_and_have_scripts() -> void:
	var registry_src := FileAccess.get_file_as_string("res://scripts/world/core/WorldEntityRegistry.gd")
	for id in PlantCatalog.wild_ids():
		var type_id := PlantCatalog.entity_type(id)
		assert_true(type_id in WorldEntityRegistry.KNOWN_PROP_TYPES, "%s nicht in KNOWN_PROP_TYPES" % type_id)
		assert_true(registry_src.contains('register_definition("%s"' % type_id), "%s nicht registriert" % type_id)
		var script := load("res://scripts/world/plants/Plant%s.gd" % id.capitalize())
		assert_not_null(script, "%s: Skript fehlt" % id)
		var obj = script.new()
		autofree(obj)
		assert_eq(obj._get_entity_type_id(), type_id)
		var data: InteractableData = obj._build_interactable_data()
		assert_eq(data.xp_type, PlantCatalog.get_plant(id)["skill"])
		assert_true(data.xp_type in SKILL_IDS, "xp_type muss ein registrierter Skill sein")
		assert_not_null(data.loot_table)
		assert_true(data.inspect_text.contains("Wusstest du?"))

func test_wild_plants_spawn_in_a_fitting_biome_and_not_in_nonsense_ones() -> void:
	var spawn := {}
	for biome_id in ["forest", "dense_forest", "meadow", "desert", "winter", "swamp", "mountain", "dead_forest"]:
		var b: BiomeDefinition = BiomeRegistry.get_biome(biome_id)
		for id in PlantCatalog.wild_ids():
			if float(b.prop_chances.get(PlantCatalog.entity_type(id), 0.0)) > 0.0:
				spawn[id] = spawn.get(id, []) + [biome_id]
	for id in PlantCatalog.wild_ids():
		assert_true(spawn.has(id), "%s spawnt in keinem Biom" % id)
	# Habitat-Logik (docs/herbalism-and-gardening.md): Mädesüß feucht, Thymian/Lavendel trocken-felsig.
	assert_true("swamp" in spawn["meadowsweet"])
	assert_true("mountain" in spawn["thyme"] and "mountain" in spawn["lavender"])
	for id in PlantCatalog.wild_ids():
		for dead in ["winter", "desert"]:
			assert_false(dead in spawn[id], "%s darf nicht in %s wachsen" % [id, dead])

func test_wild_plants_have_respawn_config() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/world/core/WorldService.gd")
	assert_true(src.contains("PlantCatalog.wild_ids()") and src.contains("WildPlant.PLANT_RESPAWN_SEC"))

func test_seeds_are_sold_in_the_shop_at_catalog_price() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/economy/shop/ShopService.gd")
	for id in PlantCatalog.ids():
		var p := PlantCatalog.get_plant(id)
		assert_true(src.contains('"%s": %d' % [p["seed_item"], p["shop_price"]]), "%s: Samen nicht im Shop" % id)

func test_village_gardens_cover_every_crop() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/world/core/WorldSpawner.gd")
	assert_true(src.contains("PlantCatalog.ids()") and src.contains('"crop_id": row_ids[i]'))

func test_meadow_flower_colors_are_real_species_hues() -> void:
	# Klatschmohn rot, Kornblume blau — die dekorativen Blumen sollen zu echten Arten passen.
	var colors: Array[Color] = BiomeRegistry.get_biome("meadow").flower_colors
	var has_red := false
	var has_blue := false
	for c in colors:
		if c.r > 0.7 and c.g < 0.25 and c.b < 0.25:
			has_red = true
		if c.b > 0.7 and c.r < 0.35:
			has_blue = true
	assert_true(has_red and has_blue)
