# res://tests/unit/test_bushes_content.gd
extends GutTest

## Sträucher (BushCatalog/WildBush): Pflücken + Roden auf EINER Entity (Wunsch 2026-10-08) sowie die
## Dichte-Regeln der Biome. Ohne Godot-Binary geschrieben — beim ersten `make test-gd` beobachten.

func _item_ids() -> Array[String]:
	var ids: Array[String] = []
	for path: String in DataManifest.ITEMS:
		var it := load(path) as ItemDefinition
		if it != null:
			ids.append(it.id)
	return ids

# ── Katalog / Daten ─────────────────────────────────────

func test_catalog_has_four_bushes_with_real_facts() -> void:
	assert_eq(BushCatalog.ids().size(), 4)
	for id in BushCatalog.ids():
		var b := BushCatalog.get_bush(id)
		for key in ["name", "latin", "pick_item", "chop_item", "pick_xp", "chop_xp", "fact", "look"]:
			assert_true(b.has(key), "%s: Feld '%s' fehlt" % [id, key])
		assert_gt(String(b["fact"]).length(), 30)
		assert_lte(String(b["fact"]).length(), 200, "%s: Fakt zu lang (Guide: ein Satz)" % id)
		assert_true(BushCatalog.inspect_text(id).contains("Wusstest du?"))

func test_items_and_loot_tables_exist() -> void:
	var items := _item_ids()
	for id in BushCatalog.ids():
		var b := BushCatalog.get_bush(id)
		assert_true(b["pick_item"] in items, "%s: Pflück-Item nicht im Manifest" % id)
		assert_true(b["chop_item"] in items, "%s: Rode-Item nicht im Manifest" % id)
		for path in [BushCatalog.pick_loot_path(id), BushCatalog.chop_loot_path(id)]:
			var loot := load(path) as LootTable
			assert_not_null(loot, "%s fehlt" % path)
		var pick := load(BushCatalog.pick_loot_path(id)) as LootTable
		assert_eq(pick.entries[0].item_id, b["pick_item"])
		var chop := load(BushCatalog.chop_loot_path(id)) as LootTable
		assert_eq(chop.entries[0].item_id, b["chop_item"])
	# Skill-Guide 5.2: Ernte-Tabellen am Objekt, NICHT im Manifest.
	for path: String in DataManifest.LOOT_TABLES:
		assert_false(path.contains("loot_bush_"), "Busch-LootTable gehört nicht ins Manifest")

# ── Entity ──────────────────────────────────────────────

func test_bush_scripts_registered_and_known() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/world/core/WorldEntityRegistry.gd")
	for id in BushCatalog.ids():
		var type_id := BushCatalog.entity_type(id)
		assert_true(type_id in WorldEntityRegistry.KNOWN_PROP_TYPES, "%s nicht in KNOWN_PROP_TYPES" % type_id)
		assert_true(src.contains('register_definition("%s"' % type_id), "%s nicht registriert" % type_id)

func test_bush_has_two_actions_pick_and_chop() -> void:
	for id in BushCatalog.ids():
		var script := load("res://scripts/world/plants/Bush%s.gd" % id.capitalize())
		assert_not_null(script, "%s: Skript fehlt" % id)
		var bush = script.new()
		add_child_autofree(bush)   # _ready() → _setup_interactable() legt beide Komponenten an
		assert_eq(bush._get_entity_type_id(), BushCatalog.entity_type(id))
		var comps: Array[InteractableComponent] = []
		for child in bush.get_children():
			if child is InteractableComponent:
				comps.append(child)
		assert_eq(comps.size(), 2, "%s: Pflücken + Roden erwartet" % id)
		var ids: Array[String] = []
		for c in comps:
			ids.append(c.data.id)
		assert_true("pick_%s" % id in ids)
		assert_true("chop_%s" % id in ids)

func test_pick_and_chop_differ_in_skill_tool_and_duration() -> void:
	var bush = load("res://scripts/world/plants/BushHazel.gd").new()
	autofree(bush)
	var pick: InteractableData = bush._build_interactable_data()
	var chop: InteractableData = bush._build_chop_data()
	assert_eq(pick.xp_type, "foraging")
	assert_eq(chop.xp_type, "woodcutting")
	assert_eq(pick.speed_stat_id, "", "Pflücken braucht kein Werkzeug")
	assert_eq(chop.speed_stat_id, "gathering_speed_wood", "Roden profitiert von der Axt wie Bäume")
	assert_gt(chop.duration, pick.duration)
	assert_not_null(pick.loot_table)
	assert_not_null(chop.loot_table)
	assert_ne(pick.loot_table, chop.loot_table)

func test_visual_builder_builds_a_bush_with_berries() -> void:
	for id in BushCatalog.ids():
		var root := Node3D.new()
		autofree(root)
		PlantVisualBuilder.build_bush(root, BushCatalog.get_bush(id)["look"], 12345)
		assert_gt(root.get_child_count(), 8, "%s: Blattkugeln + Früchte erwartet" % id)

func test_visual_builder_is_deterministic_per_seed() -> void:
	var a := Node3D.new()
	var b := Node3D.new()
	autofree(a)
	autofree(b)
	var look: Dictionary = BushCatalog.get_bush("elder")["look"]
	PlantVisualBuilder.build_bush(a, look, 99)
	PlantVisualBuilder.build_bush(b, look, 99)
	assert_eq(a.get_child_count(), b.get_child_count())
	assert_eq((a.get_child(3) as Node3D).position, (b.get_child(3) as Node3D).position)

func test_bushes_have_respawn_config() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/world/core/WorldService.gd")
	assert_true(src.contains("BushCatalog.ids()") and src.contains("BushCatalog.RESPAWN_SEC"))

# ── Biome: Sträucher + Dichte ───────────────────────────

func test_bushes_spawn_in_fitting_biomes() -> void:
	var seen := {}
	for biome_id in ["forest", "dense_forest", "meadow", "desert", "winter", "swamp", "mountain", "dead_forest"]:
		var b: BiomeDefinition = BiomeRegistry.get_biome(biome_id)
		for id in BushCatalog.ids():
			if float(b.prop_chances.get(BushCatalog.entity_type(id), 0.0)) > 0.0:
				seen[id] = seen.get(id, []) + [biome_id]
	for id in BushCatalog.ids():
		assert_true(seen.has(id), "%s spawnt in keinem Biom" % id)
		assert_false("desert" in seen[id] or "winter" in seen[id], "%s: nicht in Wüste/Schnee" % id)
	assert_true("forest" in seen["hazel"], "Haselnuss gehört in den Wald")

func test_prop_chance_sums_stay_within_one_per_biome() -> void:
	# prop_chances sind Wahrscheinlichkeiten pro Versuch; > 1.0 würde normiert (ChunkEntitySpawner._roll_weighted_type)
	# und dadurch jede einzelne Zahl heimlich verkleinern.
	for biome_id in ["forest", "dense_forest", "meadow", "desert", "winter", "swamp", "mountain", "dead_forest"]:
		var b: BiomeDefinition = BiomeRegistry.get_biome(biome_id)
		var total := 0.0
		for type_id: String in b.prop_chances.keys():
			if type_id in WorldEntityRegistry.KNOWN_PROP_TYPES:
				total += float(b.prop_chances[type_id])
		assert_lte(total, 1.0 + 0.0001, "%s: Summe der Chancen %.3f > 1" % [biome_id, total])

func test_decorative_bushes_were_reduced_in_favour_of_real_ones() -> void:
	assert_lte(BiomeRegistry.get_biome("forest").bush_per_chunk, 30)
	assert_lte(BiomeRegistry.get_biome("meadow").bush_per_chunk, 24)

func test_trees_stand_close_together() -> void:
	assert_lte(ChunkEntitySpawner.PROP_RADIUS_TREE * 2.0, 3.2, "Bäume dürfen dicht an dicht stehen (≤ 3,2 m)")
	assert_gt(ChunkEntitySpawner.PROP_RADIUS_TREE, ChunkEntitySpawner.PROP_RADIUS_SMALL)
